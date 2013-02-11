require 'rubygems'

require 'exifr'
require 'mime/types'

$:.unshift File.expand_path("../../lib", __FILE__)
require 'photohunt'

Sequel.migration do
  up do
    add_column :photos, :judges_points, Integer
    add_column :photos, :judges_notes, String, :text => true
  end
  down do
    drop_column :photos, :judges_points
    drop_column :photos, :judges_notes
  end
end
