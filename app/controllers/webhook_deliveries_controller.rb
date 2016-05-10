class WebhookDeliveriesController < ApplicationController
  respond_to :html, :js

  before_action :set_namespace
  before_action :set_webhook
  before_action :set_webhook_delivery

  after_action :verify_authorized

  # PATCH/PUT /namespaces/1/webhooks/1/deliveries/1
  def update
    authorize @webhook_delivery

    @webhook_delivery.retrigger
    render template: "webhooks/retrigger", locals: { webhook_delivery: @webhook_delivery }
  end

  def set_namespace
    @namespace = Namespace.find(params[:namespace_id])
  end

  def set_webhook
    @webhook = @namespace.webhooks.find(params[:webhook_id])
  end

  def set_webhook_delivery
    @webhook_delivery = @webhook.deliveries.find(params[:id])
  end
end
