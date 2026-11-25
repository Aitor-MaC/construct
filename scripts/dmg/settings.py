# Ajustes de dmgbuild para el DMG de Construct.
# Uso: uvx --from 'dmgbuild==1.6.5' dmgbuild -s scripts/dmg/settings.py \
#        -D app=<ruta a Construct.app> -D assets=scripts/dmg Construct <salida.dmg>
import os.path

# dmgbuild ejecuta este archivo sin __file__ e inyecta `defines` con los -D.
app = defines["app"]  # noqa: F821
here = os.path.abspath(defines.get("assets", "scripts/dmg"))  # noqa: F821
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "APFS"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")  # icono del volumen montado
hide_extension = [app_name]

background = os.path.join(here, "background.tiff")
window_rect = ((200, 140), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
arrange_by = None
icon_size = 128
text_size = 13
label_pos = "bottom"
# Deben coincidir con APP_X / APPS_X / ICON_Y de build_background.py.
icon_locations = {app_name: (180, 200), "Applications": (480, 200)}
