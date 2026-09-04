# Security Policy

## Supported versions

Only the latest PinAbove release is supported. PinAbove currently requires
yabai v7.1.16.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature instead of opening
a public issue. Include reproduction steps, affected versions, and potential
impact. Do not include passwords, private keys, or other personal data.

## Security boundary

PinAbove does not run as root or change SIP. Its core feature depends on yabai's
scripting addition, which requires a separately configured partial-SIP setup.
Users should review yabai's security documentation before enabling it.

