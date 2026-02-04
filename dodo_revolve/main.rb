# Main loader for Revolve extension
# Copyright 2024 Dodo

require 'sketchup.rb'

module Dodo
  module Revolve
    # Load the revolve tool
    require File.join(PLUGIN_PATH, 'revolve_tool.rb')

    # Create toolbar and menu items
    unless file_loaded?(File.basename(__FILE__))
      # Create toolbar
      toolbar = UI::Toolbar.new('Revolve')

      # Revolve command
      cmd_revolve = UI::Command.new('Revolve') {
        Dodo::Revolve.activate_revolve_tool
      }
      cmd_revolve.tooltip = 'Revolve Profile'
      cmd_revolve.status_bar_text = 'Select a group and revolve it around an axis'
      cmd_revolve.small_icon = File.join(PLUGIN_PATH, 'icons', 'revolve_small.png')
      cmd_revolve.large_icon = File.join(PLUGIN_PATH, 'icons', 'revolve_large.png')

      toolbar.add_item(cmd_revolve)
      toolbar.show

      # Add menu item under Draw menu
      menu = UI.menu('Draw')
      menu.add_item(cmd_revolve)

      # Add context menu for groups
      UI.add_context_menu_handler do |context_menu|
        selection = Sketchup.active_model.selection
        if selection.length == 1 && selection.first.is_a?(Sketchup::Group)
          context_menu.add_item('Revolve...') {
            Dodo::Revolve.activate_revolve_tool
          }
        end
      end

      file_loaded(File.basename(__FILE__))
    end

    # Activate the revolve tool
    def self.activate_revolve_tool
      model = Sketchup.active_model
      selection = model.selection

      # Check if a group is selected
      if selection.length != 1 || !selection.first.is_a?(Sketchup::Group)
        UI.messagebox('Please select a single group as the profile to revolve.', MB_OK)
        return
      end

      # Activate the revolve tool
      tool = RevolveTool.new(selection.first)
      model.select_tool(tool)
    end

  end
end
