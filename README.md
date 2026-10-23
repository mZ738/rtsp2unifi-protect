# rtsp2unifi-protect

[![CI](https://github.com/mZ738/rtsp2unifi-protect/actions/workflows/ci.yml/badge.svg)](https://github.com/mZ738/rtsp2unifi-protect/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/mZ738/rtsp2unifi-protect?sort=semver)](https://github.com/mZ738/rtsp2unifi-protect/releases) [![Image](https://img.shields.io/badge/ghcr.io-mz738%2Frtsp2unifi--protect-blue)](https://github.com/mZ738/rtsp2unifi-protect/pkgs/container/rtsp2unifi-protect)

Turns any RTSP stream into a virtual Onvif camera, so an NVR that only accepts Onvif devices can adopt, show and record it. Built and tested against **UniFi Protect**, which takes third-party cameras only through Onvif; it works with other Onvif Profile S clients as well.

Typical uses:

- **Cameras Protect would not take** - consumer models without Onvif, or with an Onvif implementation Protect rejects.
- **One source, many consumers** - put [go2rtc](https://github.com/AlexxIT/go2rtc) in front of the camera and feed Protect, home automation and object detection from one session.
- **Multi-channel recorders** - split a Dahua/Hikvision XVR or a multi-lens camera into one virtual camera per channel.
- **Motion from your own detector** - let Frigate, Home Assistant or anything else that speaks MQTT decide what counts as motion, and have Protect record on it.

## How it works

```
camera ──RTSP──▶ go2rtc (recommended) ──RTSP──▶ virtual Onvif camera ──Onvif + RTSP──▶ NVR
                                                (this server)                            │
MQTT motion topic ──────────────────────────────▶ Onvif events (PullPoint) ─────────────┘
```

- Every virtual camera has **its own IP address** and answers WS-Discovery and the Onvif SOAP services there.
- RTSP and snapshot connections to that address are **forwarded byte for byte** to the real source. Nothing is transcoded, nothing is re-encoded.
- Motion is **not detected here**. It arrives on one MQTT topic per camera and is passed on as Onvif events; the NVR sees plain "motion on/off", whatever triggered it.

## Features

| | |
|---|---|
| **Onvif Profile S** | Device and media services, two profiles (high and low quality), snapshot URI, WS-Discovery with accurate scopes: no PTZ scope without PTZ, no phantom relay outputs |
| **Audio** | Advertises the stream's audio track (AAC and others) so the NVR offers sound; the track itself passes through unchanged ([Audio](docs/configuration.md#audio)) |
| **Motion events** | Onvif PullPoint event service fed from MQTT; `resetAfter` as a safety net against a lost "off". UniFi Protect 7.1.55+ shows and records them ([Motion events](docs/configuration.md#motion-events)) |
| **UniFi Protect 7.2** | Answers the encoder and time requests newer Protect versions make, reports the configured stream and the host clock ([details](docs/unifi-protect.md#encoding-and-time-settings)) |
| **Device identity** | `manufacturer` and `model` per camera decide what the NVR shows when offering the device ([Configuration](docs/configuration.md)) |
| **Multi-channel sources** | One virtual camera per channel of a recorder or multi-lens camera; `--create-config` probes a real Onvif device and writes the config for you |
| **`--check`** | Validates the config and shows exactly what would be served, without opening a port - usable as `ExecStartPre=` ([Check before you restart](docs/running.md#check-before-you-restart)) |
| **Starts without internet** | The Onvif/OASIS/W3C schemas the WSDLs import are stored locally with `npm run vendor-schemas`; a failed schema load stops the start with a clear message instead of a server that answers HTTP 500 ([details](docs/running.md#starting-without-internet-access)) |
| **Prometheus metrics** | Per-connection traffic, idle time of every forwarded connection (catches frozen streams the NVR still reports as "connected"), SOAP requests and faults, event subscriptions, motion and MQTT state ([Metrics](docs/configuration.md#metrics)) |
| **Robust forwarding** | One forwarder per address and port, TCP keepalive so dead NVR connections are noticed in seconds, idle metrics for a watchdog |
| **Operations** | Config validation with precise messages, JSON logs with `LOG_FORMAT=json`, passwords only through the environment, systemd and Docker Compose examples, multi-arch image on every release |
| **Three runtime dependencies** | `node-soap`, `xml2js`, `mqtt`, nothing else; Node.js 24+, tested on 24 and 26 |

Not included: PTZ, two-way audio, Onvif authentication (the server accepts any credentials - restrict its ports by network or firewall), H.265 (advertised as H.264 only).

## Quick start

Requirements: **Node.js 24+**, one free IP address per virtual camera on the NVR's network, and an H.264 source (RTSP).

```bash
git clone https://github.com/mZ738/rtsp2unifi-protect.git
cd rtsp2unifi-protect
git checkout v2.2.0             # a release tag; main is the development branch
npm ci --omit=dev
npm run vendor-schemas          # store the Onvif schemas locally (needs internet once)

cp examples/config/front-door.yaml config.yaml   # then edit, see docs/configuration.md
node main.js --check config.yaml                 # dry run: what would be served?
node main.js config.yaml
```

Or run the published image, one container per camera on a macvlan network - see [Docker Compose](docs/running.md#docker-compose):

```bash
docker pull ghcr.io/mz738/rtsp2unifi-protect:2.2
```

The virtual cameras then show up for adoption in UniFi Protect, named after `manufacturer` and `model` (default "Onvif Cardinal"). See [Adopting in UniFi Protect](docs/unifi-protect.md) - including what Protect fixes at adoption and when a camera has to be adopted again.

To generate a config from a real Onvif camera or recorder instead of writing it:

```bash
node main.js --create-config
```

## Documentation

| | |
|---|---|
| [Configuration](docs/configuration.md) | All keys, wrapping a plain RTSP stream, audio, motion events, metrics |
| [Running](docs/running.md) | `--check`, systemd, Docker Compose, one address per camera, starting without internet |
| [UniFi Protect](docs/unifi-protect.md) | Adoption, feature support by Protect version, what Protect remembers, AI Port |
| [Troubleshooting](docs/troubleshooting.md) | One MAC per camera IP, frozen pictures, rebooting cameras, Wi-Fi drop-outs, missing events, HTTP 500, Reolink notes |
| [CHANGELOG](CHANGELOG.md) | What each release contains, how releases are cut |

## Development

```bash
npm ci
npm test            # stores the schemas first (pretest), then runs node --test
```

| Path | Content |
|---|---|
| `main.js` | CLI, startup, shutdown |
| `src/onvif-server.js` | Onvif device and media services, discovery |
| `src/event-service.js`, `src/mqtt-motion.js` | Onvif events (PullPoint), motion input from MQTT |
| `src/tcp-proxy.js`, `src/forwards.js` | RTSP/snapshot forwarding |
| `src/metrics.js`, `src/check.js`, `src/config-schema.js` | Metrics, `--check`, config validation |
| `src/config-builder.js` | `--create-config`: probing a real Onvif device |
| `scripts/vendor-schemas.js` | Local copy of the imported schemas |
| `scripts/protect-release-watch.js` | Weekly check of Ubiquiti's release notes for third-party camera changes (opens an issue) |

Releases: `npm version <major|minor|patch>`, `git push --follow-tags`; the [release workflow](.github/workflows/release.yml) runs the tests, publishes the image and creates the GitHub release. Issues and pull requests are welcome.

## History, credits and license

This project descends from [daniela-hase/onvif-server](https://github.com/daniela-hase/onvif-server) by Daniela Hasenbring, modernized by David Coulson in [davidcoulson/onvif-server](https://github.com/davidcoulson/onvif-server) ([MODERNIZATION.md](MODERNIZATION.md) describes that step). It continued as the fork [mZ738/onvif-server](https://github.com/mZ738/onvif-server) (releases 2.1.0 to 2.1.2, now archived) and has lived in this repository since October 2026. The internal names `onvif-server` (systemd unit example, metric prefix `onvif_server_*`, default MQTT client id) are kept from that lineage so existing installations keep working.

MIT licensed, see [LICENSE](LICENSE).
