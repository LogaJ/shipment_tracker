# frozen_string_literal: true

require 'git_repository_loader'

require 'active_model'

module Forms
  class FeatureReviewForm
    extend ActiveModel::Naming
    include ActiveModel::AttributeMethods
    include ActiveModel::Validations

    def to_key
      nil
    end

    def initialize(apps:, git_repository_loader: nil)
      @apps = apps
      @git_repository_loader = git_repository_loader
    end

    def valid?
      errors.add(:base, 'Please specify at least one application version') if apps.empty?
      apps.each do |repo_name, version|
        begin
          repo = git_repository_loader.load(repo_name.to_s)
          errors.add(repo_name, "#{version} does not exist or is too short") unless repo.exists?(version)
        rescue GitRepositoryLoader::NotFound
          errors.add(repo_name, 'does not exist')
        end
      end
      errors.empty?
    end

    def path
      hash = {}
      hash[:apps] = apps
      "/feature_reviews?#{hash.to_query}"
    end

    def apps
      return {} unless @apps
      @apps.select { |_app_name, version| version.present? }
    end

    private

    attr_reader :git_repository_loader
  end
end
