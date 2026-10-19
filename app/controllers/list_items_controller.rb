class ListItemsController < ApplicationController
  include ActionView::RecordIdentifier

  NEW_LIST_ITEM_FORM_IDS = %w[
    new-list-item-form-top
    new-list-item-form-bottom
  ].freeze

  before_action :authenticate_user!

  def create
    @list = find_list

    @list_item = @list.list_items.build(list_item_params)

    created = @list.with_lock do
      @list_item.save
    end

    if created
      load_list_items

      respond_to do |format|
        format.turbo_stream do
          render "list_items/update", locals: { message: t(".success") }, status: :created
        end
        format.html do
          redirect_to list_url(@list), status: :see_other
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render "list_items/form_error", locals: { list: @list, list_item: @list_item, form_id: form_id_param, message: t(".error") }, status: :unprocessable_entity
        end
        format.html do
          load_list_items

          flash.now[:error] = t(".error")

          render "lists/show", status: :unprocessable_entity
        end
      end
    end
  end

  def update
    @list_item = find_list_item

    @list = @list_item.list

    if @list_item.update(list_item_params)
      load_list_items

      respond_to do |format|
        format.turbo_stream do
          render "list_items/update", locals: { message: t(".success") }
        end
        format.html do
          redirect_to list_url(@list), status: :see_other
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render "list_items/form_error", locals: { list: @list, list_item: @list_item, form_id: dom_id(@list_item, :edit_form),  message: t(".error") }, status: :unprocessable_entity
        end
        format.html do
          load_list_items

          flash.now[:error] = t(".error")

          render "lists/show", status: :unprocessable_entity
        end
      end
    end
  end

  def destroy
    @list_item = find_list_item

    @list = @list_item.list

    if @list_item.destroy
      load_list_items

      respond_to do |format|
        format.turbo_stream do
          render "list_items/update", locals: { message: t(".success") }
        end
        format.html do
          redirect_to list_url(@list), status: :see_other
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render "list_items/destroy_error", locals: { message: t(".error") }, status: :unprocessable_entity
        end
        format.html do
          load_list_items

          flash.now[:error] = t(".error")

          render "lists/show", status: :unprocessable_entity
        end
      end
    end
  end

  def reorder
    positions = reorder_positions

    list = find_list

    reordered = list.with_lock do
      next false unless valid_reorder_positions?(list, positions)

      list_items_by_id = list.list_items.where(id: positions.map { |position| position[:id] }).index_by(&:id)

      positions.each do |position|
        list_items_by_id.fetch(position[:id]).update!(priority: position[:priority], position: position[:position])
      end
    end

    if reordered
      head :no_content
    else
      render json: { error: t(".invalid_list_item_positions") }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: t(".error"), details: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def find_list
    current_user.lists.friendly.find(params[:list_id])
  end

  def find_list_item
    find_list.list_items.find(params[:id])
  end

  def load_list_items
    @list_items = @list.list_items.ordered.includes(:purchases)

    @list_items_by_priority = @list_items.group_by(&:priority)
  end

  def list_item_params
    params.require(:list_item).permit(:name, :notes, :url, :price, :quantity, :priority, :visible)
  end

  def reorder_positions
    positions = params.permit(positions: [ :id, :priority, :position ])[:positions]

    return unless positions.is_a?(Array)

    positions.map do |position|
      return unless position.is_a?(ActionController::Parameters)

      { id: Integer(position[:id].to_s, 10), position: Integer(position[:position].to_s, 10), priority: position[:priority] }
    end
  rescue ArgumentError
    nil
  end

  def form_id_param
    params.require(:form_id).tap do |form_id|
      raise ActionController::BadRequest unless NEW_LIST_ITEM_FORM_IDS.include?(form_id)
    end
  end

  def valid_reorder_positions?(list, positions)
    return false unless positions.present?

    ids = positions.map { |position| position[:id] }
    positions_by_priority = positions.group_by { |position| position[:priority] }.transform_values { |positions| positions.map { |position| position[:position] } }

    ids.uniq.length == ids.length &&
      ids.sort == list.list_items.ids.sort &&
      positions_by_priority.keys.all? { |priority| ListItem.priorities.key?(priority) } &&
      positions_by_priority.values.all? { |positions| positions.sort == (0...positions.length).to_a }
  end
end
