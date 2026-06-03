class UpdateBrandUrlsToKonversioGithub < ActiveRecord::Migration[7.0]
  def up
    # Update the InstallationConfig values for BRAND_URL and WIDGET_BRAND_URL if they are set to the old chatwoot URL
    %w[BRAND_URL WIDGET_BRAND_URL].each do |name|
      config = InstallationConfig.find_by(name: name)
      if config && (config.value == 'https://www.chatwoot.com' || config.value.blank?)
        config.update!(value: 'https://github.com/konversio-org/konversio/')
      end
    end

    GlobalConfig.clear_cache if defined?(GlobalConfig)
  end

  def down
    # Restore the InstallationConfig values for BRAND_URL and WIDGET_BRAND_URL to the old default
    %w[BRAND_URL WIDGET_BRAND_URL].each do |name|
      config = InstallationConfig.find_by(name: name)
      config.update!(value: 'https://www.chatwoot.com') if config && config.value == 'https://github.com/konversio-org/konversio/'
    end

    GlobalConfig.clear_cache if defined?(GlobalConfig)
  end
end
