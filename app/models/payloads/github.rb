module Payloads
  class Github
    def initialize(data)
      @data = data
    end

    def before_sha
      @data['before']
    end

    def after_sha
      @data['after']
    end

    def head_sha
      @data.dig('head_commit', 'id')
    end

    def base_repo_url
      @data.dig('repository', 'html_url')
    end

    def full_repo_name
      @data.dig('repository', 'full_name')
    end
  end
end
