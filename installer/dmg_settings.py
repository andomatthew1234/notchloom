"""Finder layout for the Notchloom drag-to-Applications image."""

app_path = defines["app"]
background_path = defines["background"]

files = [app_path]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]
background = background_path
window_rect = ((180, 180), (640, 380))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = True
icon_size = 104
text_size = 13
label_pos = "bottom"
icon_locations = {"Notchloom.app": (175, 190), "Applications": (465, 190)}
format = "UDZO"
filesystem = "HFS+"
