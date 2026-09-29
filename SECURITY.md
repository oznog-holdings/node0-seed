# Reporting something that should not have been published

Everything here is meant to have passed a publication review that removes credentials,
serials, device identifiers, the owner's private names and addresses outside the Seed's own
networks. If you find something that got through, a credential or a key, a serial, a name,
an address, do not open a public issue.

Use one of these, both private and both read by the maintainers:

- [Private vulnerability reporting](https://github.com/oznog-holdings/node0-seed/security/advisories/new)
  on this repository.
- The contact in [oznog.com's security.txt](https://oznog.com/.well-known/security.txt).

Say where it is, file and line, and what you believe it exposes. You will get an
acknowledgement, and the fix goes out on the next push. Because a mirror keeps history, a fix
that has to remove something from the past is a history rewrite at the origin followed by a
fresh mirror, and any credential that was exposed is rotated at its issuer regardless of how
quickly the text was removed. The maintainers will say which of those happened.

A weakness in the Seed's design itself, something a reader would build and be exposed by, is
reported the same way, so it can be fixed on the pages before it spreads.
