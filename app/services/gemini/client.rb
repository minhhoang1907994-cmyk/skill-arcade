require "net/http"
require "json"

module Gemini
  # Client tối giản cho Gemini generateContent REST API, dựng trên net/http của
  # stdlib — không thêm dependency mới.
  #
  # Bảo mật (spec §12): API key đi trong header `x-goog-api-key`, KHÔNG nằm trong URL.
  # Nhờ vậy key không lọt vào access log hay message của exception khi request lỗi.
  #
  # Timeout: spec §15 chốt hard timeout 10s cho lời gọi lúc chơi. Sinh đề theo lô
  # chạy offline nên được truyền timeout dài hơn.
  class Client
    class RequestFailed < Error; end
    class ConfigurationError < Error; end

    HOST = "generativelanguage.googleapis.com".freeze
    API_VERSION = "v1beta".freeze
    DEFAULT_MODEL = "gemini-2.5-flash".freeze

    OPEN_TIMEOUT_SECONDS = 5
    READ_TIMEOUT_SECONDS = 10

    Response = Struct.new(:text, :raw_body, :latency_ms, keyword_init: true)

    def self.configured?
      ENV["GEMINI_API_KEY"].present?
    end

    def initialize(model: nil, api_key: nil, read_timeout: READ_TIMEOUT_SECONDS)
      @model = model.presence || ENV["GEMINI_MODEL"].presence || DEFAULT_MODEL
      @api_key = api_key.presence || ENV["GEMINI_API_KEY"].presence
      @read_timeout = read_timeout
    end

    attr_reader :model

    # response_schema: JSON Schema để Gemini trả đúng cấu trúc (structured output).
    # Bắt buộc dùng cho cả chấm điểm và sinh đề — không parse text tự do.
    def generate(prompt, response_schema:, temperature: 0.2, max_output_tokens: 2048)
      raise ConfigurationError, "GEMINI_API_KEY chưa được cấu hình" if @api_key.blank?

      started_at = now_ms
      body = post(payload(prompt, response_schema, temperature, max_output_tokens))
      Response.new(text: extract_text(body), raw_body: body, latency_ms: now_ms - started_at)
    end

    private

    def payload(prompt, response_schema, temperature, max_output_tokens)
      {
        contents: [ { role: "user", parts: [ { text: prompt } ] } ],
        generationConfig: {
          temperature: temperature,
          maxOutputTokens: max_output_tokens,
          responseMimeType: "application/json",
          responseSchema: response_schema
        }
      }
    end

    def post(payload)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["x-goog-api-key"] = @api_key
      request.body = payload.to_json

      response = http.request(request)
      parse(response)
    rescue Net::OpenTimeout, Net::ReadTimeout
      raise RequestFailed, "Gemini timeout sau #{@read_timeout}s"
    rescue SystemCallError, SocketError, IOError, OpenSSL::SSL::SSLError => e
      # Không đưa e.message của tầng socket vào response cho người chơi, nhưng vẫn
      # giữ lại để ghi vào ai_gradings.error.
      raise RequestFailed, "không gọi được Gemini: #{e.class}: #{e.message}"
    end

    def http
      Net::HTTP.new(uri.host, uri.port).tap do |client|
        client.use_ssl = true
        client.open_timeout = OPEN_TIMEOUT_SECONDS
        client.read_timeout = @read_timeout
      end
    end

    def uri
      @uri ||= URI::HTTPS.build(
        host: HOST, path: "/#{API_VERSION}/models/#{@model}:generateContent"
      )
    end

    def parse(response)
      body = begin
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        nil
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise RequestFailed,
              "Gemini trả HTTP #{response.code}: #{body&.dig('error', 'message') || response.message}"
      end

      body || raise(RequestFailed, "Gemini trả body không phải JSON")
    end

    # Chặn cả trường hợp Gemini trả 200 nhưng không có nội dung dùng được:
    # bị filter an toàn, hoặc cắt giữa chừng vì hết maxOutputTokens.
    def extract_text(body)
      if (block_reason = body.dig("promptFeedback", "blockReason")).present?
        raise RequestFailed, "Gemini từ chối prompt: #{block_reason}"
      end

      candidate = body.dig("candidates", 0)
      raise RequestFailed, "Gemini không trả candidate nào" if candidate.nil?

      finish_reason = candidate["finishReason"].to_s
      if finish_reason.present? && finish_reason != "STOP"
        raise RequestFailed, "Gemini kết thúc bất thường: #{finish_reason}"
      end

      text = candidate.dig("content", "parts", 0, "text")
      raise RequestFailed, "Gemini trả nội dung rỗng" if text.blank?

      text
    end

    def now_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    end
  end
end
