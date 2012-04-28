require 'rubygems'

require 'exifr'
require 'mime/types'

$:.unshift File.expand_path("../../lib", __FILE__)
require 'photohunt'

Sequel.migration do
  up do
    add_column :photos, :exposure, DateTime
    self[:photos].each do |photo|
      mime = MIME::Types[photo[:mime]].first
      case mime.content_type
      when "image/jpeg", "image/tiff"
        self[:photos].filter(:guid => photo[:guid]).update(:exposure => EXIFR::JPEG.new(StringIO.new(photo[:data])).date_time)
      end
    end
  end
  down do
    drop_column :photos, :exposure
  end
end
