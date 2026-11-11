# Настройки dmgbuild для установочного образа Сугроба. Вызывается из tools/dmg/make_dmg.sh:
#   dmgbuild -s settings.py -D app=<Sugrob.app> -D bg=<папка с background.png> -D icon=<AppIcon.icns> Sugrob out.dmg
import os

app = defines["app"]            # noqa: F821 — defines подставляет dmgbuild
bg = defines["bg"]              # noqa: F821
name = os.path.basename(app)

files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]          # noqa: F821 — значок самого тома

background = os.path.join(bg, "background.png")     # рядом лежит background@2x.png — dmgbuild берёт и его

format = "UDZO"
filesystem = "HFS+"

# Окно: видимая часть 660×400 — размер фона. Значки по центру левой и правой половины, на одной высоте со стрелкой.
# высота окна Finder считается вместе с заголовком (28 пунктов), поэтому 428, чтобы видимая часть была 660×400
window_rect = ((200, 140), (660, 428))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 112
text_size = 12
arrange_by = None
icon_locations = {
    name: (165, 170),
    "Applications": (495, 170),
}
