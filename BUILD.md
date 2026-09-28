```
DEV
/path/to/kwin

        ↓ rsync

BUILD SOURCE
~/build/topos/kwin/src/kwin-6.7.5

        ↓ makepkg -eLsf

PACKAGE
```

## Initial package-tree setup

Run this once after placing the Arch `PKGBUILD` in `~/build/topos/kwin`:

```bash
cd ~/build/topos/kwin
makepkg -os
```

## Build and install

The repository helper checks the source, copies it into the package tree, builds
the package, and installs it:

```bash
cd /path/to/kwin
./install-topos-kwin.sh
```

The equivalent manual build and install commands are:

```bash
rsync -a --delete --exclude=.git/ --exclude=build/ --exclude=.build/ \
    /path/to/kwin/ \
    ~/build/topos/kwin/src/kwin-6.7.5/

cd ~/build/topos/kwin
makepkg -eLsf --check
sudo pacman -U ./kwin-6.7.5-*.pkg.tar.zst
```

Log out of Plasma and log back in to start the installed KWin. To reload KWin
without logging out, save all work first and run:

```bash
kwin_wayland --replace
```

## Restore Arch's KWin

```bash
sudo pacman -S kwin
```

Then log out and back in, reboot, or run `kwin_wayland --replace`.

If Plasma cannot start, switch to a TTY with `Ctrl+Alt+F3`, log in, and run:

```bash
sudo pacman -S kwin
sudo reboot
```

If networking is unavailable, reinstall an official package from pacman's
cache:

```bash
sudo pacman -U /var/cache/pacman/pkg/kwin-<version>-x86_64.pkg.tar.zst
```

# All in One
```
rsync -a     --exclude='.git/'     --exclude='.build/'     --exclude='build/'     --exclude='repo.zip'     /path/to/kwin/     ~/build/topos/kwin/src/kwin-6.7.5/ && cd ~/build/topos/kwin/ && makepkg -eLsf && sudo pacman -U ./kwin-6.7.5-*.pkg.tar.zst && kwin_wayland --replace
```