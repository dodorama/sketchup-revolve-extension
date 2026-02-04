# Revolve Extension for SketchUp
# Creates solids by rotating a profile group around an axis

require 'sketchup.rb'
require 'extensions.rb'

module Dodo
  module Revolve
    EXTENSION_NAME = 'Revolve'.freeze
    EXTENSION_VERSION = '1.0.0'.freeze
    EXTENSION_DESCRIPTION = 'Create solids by revolving a profile around an axis'.freeze

    # Extension root path
    PLUGIN_ROOT = File.dirname(__FILE__)
    PLUGIN_PATH = File.join(PLUGIN_ROOT, 'dodo_revolve')

    # Register the extension
    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new(EXTENSION_NAME, File.join(PLUGIN_PATH, 'main.rb'))
      extension.description = EXTENSION_DESCRIPTION
      extension.version = EXTENSION_VERSION
      extension.creator = 'Dodo'
      extension.copyright = '2024'

      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
