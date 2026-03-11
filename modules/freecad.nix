# FreeCAD Tokyo Night QSS stylesheet for home-manager
#
# Generates a Qt QSS stylesheet mapping Tokyo Night dark colors to FreeCAD
# widgets. Dark-only for now. Viewport background colors require manual setup
# in FreeCAD Preferences > Display > Colors, as those are stored in user.cfg
# and not affected by QSS.
#
# The user selects the stylesheet once in Edit > Preferences > General >
# Stylesheet. It persists across sessions.
{
  config,
  pkgs,
  ...
}: let
  colorsNight = config.colorScheme.darkPalette;
  homeDir = config.home.homeDirectory;

  freecadDataBase = "${homeDir}/.var/app/org.freecad.FreeCAD/data/FreeCAD";

  # Generate a QSS stylesheet from a Tokyo Night palette.
  mkFreecadQss = p: ''
    /* Tokyo Night theme for FreeCAD */

    QWidget {
      background-color: #${p.base00};
      color: #${p.base05};
      selection-background-color: #${p.accent};
      selection-color: #${p.base00};
    }

    QMainWindow {
      background-color: #${p.panelBg};
    }

    QMainWindow::separator {
      background-color: #${p.base02};
      width: 2px;
      height: 2px;
    }

    QDockWidget {
      titlebar-close-icon: none;
      background-color: #${p.base00};
      border: 1px solid #${p.base02};
    }

    QDockWidget::title {
      background-color: #${p.panelBg};
      padding: 4px;
    }

    QTabWidget::pane {
      border: 1px solid #${p.base02};
      background-color: #${p.base00};
    }

    QTabBar::tab {
      background-color: #${p.panelBg};
      color: #${p.base04};
      padding: 6px 12px;
      border: 1px solid #${p.base02};
      border-bottom: none;
    }

    QTabBar::tab:selected {
      background-color: #${p.base00};
      color: #${p.base05};
    }

    QTabBar::tab:hover {
      background-color: #${p.base01};
    }

    QTreeView, QListView, QTableView {
      background-color: #${p.base00};
      alternate-background-color: #${p.base01};
      border: 1px solid #${p.base02};
    }

    QTreeView::item:selected, QListView::item:selected, QTableView::item:selected {
      background-color: #${p.accent};
      color: #${p.base00};
    }

    QTreeView::item:hover, QListView::item:hover {
      background-color: #${p.base02};
    }

    QHeaderView::section {
      background-color: #${p.panelBg};
      color: #${p.base05};
      padding: 4px;
      border: 1px solid #${p.base02};
    }

    QMenuBar {
      background-color: #${p.panelBg};
      color: #${p.base05};
    }

    QMenuBar::item:selected {
      background-color: #${p.base02};
    }

    QMenu {
      background-color: #${p.base01};
      color: #${p.base05};
      border: 1px solid #${p.base02};
    }

    QMenu::item:selected {
      background-color: #${p.accent};
      color: #${p.base00};
    }

    QMenu::separator {
      height: 1px;
      background-color: #${p.base02};
    }

    QToolBar {
      background-color: #${p.panelBg};
      border: none;
      spacing: 2px;
    }

    QToolButton {
      background-color: transparent;
      border: 1px solid transparent;
      border-radius: 4px;
      padding: 2px;
    }

    QToolButton:hover {
      background-color: #${p.base02};
      border-color: #${p.base02};
    }

    QToolButton:pressed {
      background-color: #${p.base01};
    }

    QToolButton:checked {
      background-color: #${p.base02};
      border-color: #${p.accent};
    }

    QScrollBar:vertical {
      background-color: #${p.base00};
      width: 12px;
      border: none;
    }

    QScrollBar::handle:vertical {
      background-color: #${p.base02};
      border-radius: 4px;
      min-height: 20px;
      margin: 2px;
    }

    QScrollBar::handle:vertical:hover {
      background-color: #${p.base03};
    }

    QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
      height: 0;
    }

    QScrollBar:horizontal {
      background-color: #${p.base00};
      height: 12px;
      border: none;
    }

    QScrollBar::handle:horizontal {
      background-color: #${p.base02};
      border-radius: 4px;
      min-width: 20px;
      margin: 2px;
    }

    QScrollBar::handle:horizontal:hover {
      background-color: #${p.base03};
    }

    QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {
      width: 0;
    }

    QLineEdit, QTextEdit, QPlainTextEdit, QSpinBox, QDoubleSpinBox {
      background-color: #${p.base01};
      color: #${p.base05};
      border: 1px solid #${p.base02};
      border-radius: 4px;
      padding: 2px 4px;
    }

    QLineEdit:focus, QTextEdit:focus, QPlainTextEdit:focus {
      border-color: #${p.accent};
    }

    QPushButton {
      background-color: #${p.base02};
      color: #${p.base05};
      border: 1px solid #${p.base03};
      border-radius: 4px;
      padding: 4px 12px;
    }

    QPushButton:hover {
      background-color: #${p.base03};
    }

    QPushButton:pressed {
      background-color: #${p.base01};
    }

    QPushButton:default {
      border-color: #${p.accent};
    }

    QComboBox {
      background-color: #${p.base01};
      color: #${p.base05};
      border: 1px solid #${p.base02};
      border-radius: 4px;
      padding: 2px 4px;
    }

    QComboBox::drop-down {
      border: none;
    }

    QComboBox QAbstractItemView {
      background-color: #${p.base01};
      color: #${p.base05};
      selection-background-color: #${p.accent};
      selection-color: #${p.base00};
      border: 1px solid #${p.base02};
    }

    QStatusBar {
      background-color: #${p.panelBg};
      color: #${p.base04};
    }

    QToolTip {
      background-color: #${p.base01};
      color: #${p.base05};
      border: 1px solid #${p.base02};
      padding: 4px;
    }

    QGroupBox {
      border: 1px solid #${p.base02};
      border-radius: 4px;
      margin-top: 8px;
      padding-top: 8px;
    }

    QGroupBox::title {
      color: #${p.base06};
      subcontrol-origin: margin;
      padding: 0 4px;
    }

    QCheckBox::indicator, QRadioButton::indicator {
      width: 14px;
      height: 14px;
    }

    QProgressBar {
      background-color: #${p.base01};
      border: 1px solid #${p.base02};
      border-radius: 4px;
      text-align: center;
      color: #${p.base05};
    }

    QProgressBar::chunk {
      background-color: #${p.accent};
      border-radius: 3px;
    }

    QSplitter::handle {
      background-color: #${p.base02};
    }
  '';

  tokyoNightQss = pkgs.writeText "tokyo-night.qss" (mkFreecadQss colorsNight);
in {
  # Deploy QSS stylesheet to each versioned FreeCAD data directory.
  home.activation.deployFreecadTheme = config.lib.dag.entryAfter ["writeBoundary"] ''
    base="${freecadDataBase}"
    for data_dir in "$base"/*/; do
      [ -d "$data_dir" ] || continue
      mkdir -p "$data_dir/Gui/Stylesheets"
      rm -f "$data_dir/Gui/Stylesheets/tokyo-night.qss"
      cp "${tokyoNightQss}" "$data_dir/Gui/Stylesheets/tokyo-night.qss"
      chmod 644 "$data_dir/Gui/Stylesheets/tokyo-night.qss"
    done
  '';
}
