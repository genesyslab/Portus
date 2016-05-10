# == Schema Information
#
# Table name: webhooks
#
#  id             :integer          not null, primary key
#  namespace_id   :integer
#  url            :string(255)
#  username       :string(255)
#  password       :string(255)
#  request_method :integer
#  content_type   :integer
#  enabled        :boolean          default("0")
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_webhooks_on_namespace_id  (namespace_id)
#

require "base64"
require "typhoeus"
require "securerandom"
require "json"

class Webhook < ActiveRecord::Base
  include PublicActivity::Common

  enum request_method: ["GET", "POST"]
  enum content_type: ["application/json", "application/x-www-form-urlencoded"]

  belongs_to :namespace

  has_many :deliveries, class_name: "WebhookDelivery"
  has_many :headers, class_name: "WebhookHeader"

  validates :url, presence: true

  before_destroy :update_activities!

  # Handle a push event from the registry. All enabled webhooks of the provided
  # namespace are triggered in parallel.
  def self.handle_push_event(event)
    namespace = Namespace.find_from_event(event)
    return if namespace.nil?

    hydra = Typhoeus::Hydra.hydra

    Webhook.where(namespace: namespace).find_each do |webhook|
      next unless webhook.enabled

      headers, auth = headers_from_webhook(webhook)

      args = {
        method:  webhook.request_method,
        headers: headers,
        body:    JSON.generate(event),
        timeout: 60
      }
      args[:userpwd] = auth unless auth.empty?

      request = Typhoeus::Request.new(webhook.url, args)

      request.on_complete do |response|
        # prevent uuid clash
        loop do
          @uuid = SecureRandom.uuid
          break if WebhookDelivery.find_by(webhook_id: webhook.id, uuid: @uuid).nil?
        end

        WebhookDelivery.create(
          webhook_id:      webhook.id,
          uuid:            @uuid,
          status:          response.response_code,
          request_header:  headers.to_s,
          request_body:    JSON.generate(event),
          response_header: response.response_headers,
          response_body:   response.response_body)
      end

      hydra.queue request
    end

    hydra.run
  end

  private

  # Provide useful parameters for the "timeline" when a webhook has been
  # removed.
  def update_activities!
    PublicActivity::Activity.where(trackable: self).update_all(
      parameters: {
        namespace_id:   namespace.id,
        namespace_name: namespace.clean_name,
        webhook_url:    url
      }
    )
  end

  def self.headers_from_webhook(webhook)
    headers = { "Content-Type" => webhook.content_type }
    WebhookHeader.where(webhook: webhook).find_each do |header|
      headers[header.name] = header.value
    end
    if webhook.username.empty? || webhook.password.empty?
      auth = ""
    else
      auth = "#{webhook.username}:#{webhook.password}"
    end
    [headers, auth]
  end
end
