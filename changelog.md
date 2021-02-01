# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.2] - 2021-02-01

### Fixed
- Typo on stop procedure (*has* been stopped).

## [1.1.1] - 2021-01-18

### Changed
- Config : New 'files' section
- CSV Datasource : powerOn and PowerOff fields changed from integer (0|1) to boolean (true|false), coherence with enabled and useTLS fields.

### Fixed
- Config : Fix logs.directory not used ('/var/log/' forced)

## [1.1.0] - 2020-12-20

### Added
- Power management support with GPIO on Raspberry Pi (powerGpio, powerOn, powerOff)

## [1.0.0] - 2020-09-23

- Initial release