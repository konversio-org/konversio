require 'rubygems/package'

class Geocoder::SetupService
  BUCKET_KEY = 'GeoLite2-City.mmdb'

  def perform
    return if File.exist?(GeocoderConfiguration::LOOK_UP_DB)

    ip_lookup_api_key = ENV.fetch('IP_LOOKUP_API_KEY', nil)
    if ip_lookup_api_key.blank?
      log_info('IP_LOOKUP_API_KEY empty. Skipping geoip database setup')
      return
    end

    FileUtils.mkdir_p(File.dirname(GeocoderConfiguration::LOOK_UP_DB))

    if fetch_from_bucket
      log_info('Loaded GeoLite2-City database from storage bucket')
    else
      log_info('Fetching GeoLite2-City database from MaxMind')
      fetch_and_extract_database(ip_lookup_api_key)
      upload_to_bucket
    end
  end

  private

  def s3_client
    @s3_client ||= begin
      require 'aws-sdk-s3'
      Aws::S3::Client.new(
        access_key_id: ENV.fetch('STORAGE_ACCESS_KEY_ID', nil),
        secret_access_key: ENV.fetch('STORAGE_SECRET_ACCESS_KEY', nil),
        region: ENV.fetch('STORAGE_REGION', 'us-east-1'),
        endpoint: ENV.fetch('STORAGE_ENDPOINT', nil),
        force_path_style: ENV.fetch('STORAGE_FORCE_PATH_STYLE', 'false') == 'true'
      )
    end
  end

  def bucket_name
    ENV.fetch('STORAGE_BUCKET_NAME', nil)
  end

  def bucket_configured?
    bucket_name.present? && ENV['STORAGE_ACCESS_KEY_ID'].present?
  end

  def fetch_from_bucket
    return false unless bucket_configured?

    s3_client.get_object(bucket: bucket_name, key: BUCKET_KEY, response_target: GeocoderConfiguration::LOOK_UP_DB.to_s)
    true
  rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NotFound
    false
  rescue StandardError => e
    log_error("Bucket fetch failed: #{e.message}")
    false
  end

  def upload_to_bucket
    return unless bucket_configured? && File.exist?(GeocoderConfiguration::LOOK_UP_DB)

    s3_client.put_object(
      bucket: bucket_name,
      key: BUCKET_KEY,
      body: File.open(GeocoderConfiguration::LOOK_UP_DB, 'rb')
    )
    log_info('Uploaded GeoLite2-City database to storage bucket')
  rescue StandardError => e
    log_error("Bucket upload failed: #{e.message}")
  end

  def fetch_and_extract_database(api_key)
    base_url = ENV.fetch('IP_LOOKUP_BASE_URL', 'https://download.maxmind.com/app/geoip_download')
    source_file = Down.download("#{base_url}?edition_id=GeoLite2-City&suffix=tar.gz&license_key=#{api_key}")

    extract_tar_file(source_file)
    log_info('Fetch complete')
  rescue StandardError => e
    log_error(e.message)
  end

  def extract_tar_file(source_file)
    tar_extract = Gem::Package::TarReader.new(Zlib::GzipReader.open(source_file))
    tar_extract.rewind

    tar_extract.each do |entry|
      next unless entry.full_name.include?('GeoLite2-City.mmdb') && entry.file?

      File.open GeocoderConfiguration::LOOK_UP_DB, 'wb' do |f|
        f.print entry.read
      end
    end
  end

  def log_info(message)
    Rails.logger.info "[rake ip_lookup:setup] #{message}"
  end

  def log_error(message)
    Rails.logger.error "[rake ip_lookup:setup] #{message}"
  end
end
