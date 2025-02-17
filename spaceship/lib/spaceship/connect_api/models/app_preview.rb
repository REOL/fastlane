require_relative '../model'
require_relative '../file_uploader'
require 'spaceship/globals'

require 'digest/md5'

module Spaceship
  class ConnectAPI
    class AppPreview
      include Spaceship::ConnectAPI::Model

      attr_accessor :file_size
      attr_accessor :file_name
      attr_accessor :source_file_checksum
      attr_accessor :preview_frame_time_code
      attr_accessor :mime_type
      attr_accessor :video_url
      attr_accessor :preview_image
      attr_accessor :upload_operations
      attr_accessor :asset_deliver_state
      attr_accessor :upload

      attr_mapping({
        "fileSize" => "file_size",
        "fileName" => "file_name",
        "sourceFileChecksum" => "source_file_checksum",
        "previewFrameTimeCode" => "preview_frame_time_code",
        "mimeType" => "mime_type",
        "videoUrl" => "video_url",
        "previewImage" => "preview_image",
        "uploadOperations" => "upload_operations",
        "assetDeliveryState" => "asset_delivery_state",
        "uploaded" => "uploaded"
      })

      def self.type
        return "appPreviews"
      end

      def complete?
        (asset_delivery_state || {})["state"] == "COMPLETE"
      end

      #
      # API
      #

      def self.get(app_preview_id: nil)
        Spaceship::ConnectAPI.get_app_preview(app_preview_id: app_preview_id).first
      end

      # Creates an AppPreview in an AppPreviewSet
      # Setting the optional frame_time_code will force polling until video is done processing
      # @param app_preview_set_id The AppPreviewSet id
      # @param path The path of the file
      # @param frame_time_code The time code for the preview still frame (ex: "00:00:07:01")
      def self.create(app_preview_set_id: nil, path: nil, frame_time_code: nil)
        require 'faraday'

        filename = File.basename(path)
        filesize = File.size(path)
        bytes = File.binread(path)

        post_attributes = {
          fileSize: filesize,
          fileName: filename
        }

        # Create placeholder
        preview = Spaceship::ConnectAPI.post_app_preview(
          app_preview_set_id: app_preview_set_id,
          attributes: post_attributes
        ).to_models.first

        # Upload the file
        upload_operations = preview.upload_operations
        Spaceship::ConnectAPI::FileUploader.upload(upload_operations, bytes)

        # Update file uploading complete
        patch_attributes = {
          uploaded: true,
          sourceFileChecksum: Digest::MD5.hexdigest(bytes)
        }

        begin
          preview = Spaceship::ConnectAPI.patch_app_preview(
            app_preview_id: preview.id,
            attributes: patch_attributes
          ).to_models.first
        rescue => error
          puts("Failed to patch app preview. Update may have gone through so verifying") if Spaceship::Globals.verbose?

          preview = Spaceship::ConnectAPI::AppPreview.get(app_preview_id: preview.id)
          raise error unless preview.complete?
        end

        # Poll for video processing completion to set still frame time
        unless frame_time_code.nil?
          loop do
            unless preview.video_url.nil?
              puts("Preview processing complete!") if Spaceship::Globals.verbose?
              preview = preview.update(attributes: {
                previewFrameTimeCode: frame_time_code
              })
              puts("Updated preview frame time code!") if Spaceship::Globals.verbose?
              break
            end

            sleep_time = 30
            puts("Waiting #{sleep_time} seconds before checking status of processing...") if Spaceship::Globals.verbose?
            sleep(sleep_time)

            preview = Spaceship::ConnectAPI::AppPreview.get(app_preview_id: preview.id)
          end
        end

        preview
      end

      def update(attributes: nil)
        Spaceship::ConnectAPI.patch_app_preview(app_preview_id: id, attributes: attributes)
      end

      def delete!(filter: {}, includes: nil, limit: nil, sort: nil)
        Spaceship::ConnectAPI.delete_app_preview(app_preview_id: id)
      end
    end
  end
end
