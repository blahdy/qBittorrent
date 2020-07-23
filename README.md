qBittorrent for macOS 10.14+ Light mode with its theme modded to actually adhear to macOS environment.

For the dark themed version select the "master" branch.

Most of the graphics used is from [La Capitaine icon pack](https://github.com/keeferrourke/la-capitaine-icon-theme).

These releases are pure alpha with everything, incl. the dependencies, built from development sources thanks to a [script by Kolcha](https://gist.github.com/Kolcha/3ccd533123b773ba110b8fd778b1c2bf). If something doesn't work - I cannot help you.

Apart from the graphics there are two other differences from the original: sequential download is enabled by default and the version reported to the tracker is faked to be stable (according to the current stable official at the time of build).

To prevent the system dialogue asking for incoming connections permission from reappearing with the system firewall enabled - enter the following in terminal:

sudo codesign --force --deep --sign - /Applications/qbittorrent.app/
