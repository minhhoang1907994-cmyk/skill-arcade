require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Cache store PHẢI dùng chung giữa các instance và sống sót qua deploy.
  #
  # Mặc định của Rails là file store ở tmp/cache. Trên Render thì filesystem là ephemeral và
  # riêng từng instance, nên file store làm MẤT hai thứ mỗi lần deploy hoặc spin down:
  # - bộ đếm rack_attack, gồm throttle 1 lượt/ngày của Spec Detective (§12) — mất là người chơi
  #   được lượt mới, throttle gần như vô hiệu vì web service gói Hobby tự ngủ khi không có traffic
  # - trạng thái Gemini::CircuitBreaker (§15)
  # Gemini::DailyBudget không bị ảnh hưởng vì đếm từ bảng ai_gradings, không dùng cache.
  #
  # Không có REDIS_URL thì vẫn boot được nhưng cảnh báo rõ ràng, để sự xuống cấp này không âm
  # thầm — thà log ầm lên còn hơn để throttle hỏng mà không ai biết.
  if ENV["REDIS_URL"].present?
    config.cache_store = :redis_cache_store, {
      url: ENV["REDIS_URL"],
      connect_timeout: 1,
      read_timeout: 1,
      write_timeout: 1,
      reconnect_attempts: 1,
      # Redis chết thì cache miss, KHÔNG được làm sập request. Cache miss với rack_attack nghĩa
      # là tạm thời không chặn, chấp nhận được hơn là toàn bộ app trả 500.
      error_handler: lambda { |method:, returning:, exception:|
        Rails.logger.error("[cache] redis lỗi ở #{method}: #{exception.class}: #{exception.message}")
      }
    }
  else
    # Phải hoãn tới after_initialize: trong lúc file này đang được nạp thì Rails.logger vẫn còn
    # nil, gọi thẳng sẽ ném NoMethodError và app KHÔNG boot được — nghĩa là thiếu REDIS_URL sẽ
    # làm sập deploy thay vì chỉ xuống cấp.
    config.after_initialize do
      Rails.logger.warn(
        "[cache] REDIS_URL chưa được set — dùng file store. rack_attack và circuit breaker sẽ " \
        "mất trạng thái mỗi lần deploy/restart và không dùng chung giữa các instance."
      )
    end
  end

  # Replace the default in-process and non-durable queuing backend for Active Job.
  # config.active_job.queue_adapter = :resque

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
