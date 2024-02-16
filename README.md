# SBOM generation for RPM database

This repository contains basic tool to generate CycloneDX SBOM based on the installed system RPM database on SUSE and openSUSE systems.

Recommended usage is to install `sbom-plugin.sh` to `/usr/lib/zypp/plugins/commit/`

Each `zypper` command installing / updating / removing packages will update SBOM stored in `/usr/lib/sysimage/rpm/`

The best experience is achieved on transactional system : each snapshot will carry its associated SBOM.

To compare sbom, you can use [sbomdiff](<https://github.com/anthonyharrison/sbomdiff>). For instance:

`sbomdiff /.snapshots/*NUMBER*/snapshot/usr/lib/sysimage/rpm/sbom.cdx.json /usr/lib/sysimage/rpm/sbom.cdx.json`
