class ListItemsController < ApplicationController
  def create
    @list = find_list

    @list_item = @list.list_items.build(list_item_params)

    if @list_item.save
      @list_items = @list.list_items.ordered.includes(:purchases)

      @list_items_by_priority = @list_items.group_by(&:priority)

      respond_to do |format|
        format.turbo_stream do
          render "list_items/update", locals: { message: t(".success") }, status: :created
        end
        format.html do
          render partial: "list_items/list_items", status: :created
        end
      end
    else
      render partial: "list_items/form", locals: { list: @list, list_item: @list_item }, status: :unprocessable_entity
    end
  end

  def update
    @list_item = find_list_item

    @list = @list_item.list

    if @list_item.update(list_item_params)
      @list_items = @list.list_items.ordered.includes(:purchases)

      @list_items_by_priority = @list_items.group_by(&:priority)

      respond_to do |format|
        format.turbo_stream do
          render "list_items/update", locals: { message: t(".success") }
        end
        format.html do
          render partial: "list_items/list_items"
        end
      end
    else
      render partial: "list_items/form", locals: { list: @list, list_item: @list_item }, status: :unprocessable_entity
    end
  end

  def destroy
    @list_item = find_list_item

    @list = @list_item.list

    if @list_item.destroy
      @list_items = @list.list_items.ordered.includes(:purchases)

      @list_items_by_priority = @list_items.group_by(&:priority)

      respond_to do |format|
        format.turbo_stream do
          render "list_items/update", locals: { message: t(".success") }
        end
        format.html do
          render partial: "list_items/list_items"
        end
      end
    else
      flash[:error] = t(".error")

      render partial: "list_items/list_items", status: :unprocessable_entity
    end
  end

  def reorder
    positions = positions_params[:positions]

    list = find_list

    unless valid_reorder_positions?(list, positions)
      return render json: { error: t(".invalid_list_item_positions") }, status: :unprocessable_entity
    end

    list_items_by_id = list.list_items.where(id: positions.map { |position| position[:id] }).index_by(&:id)

    ListItem.transaction do
      positions.each do |position|
        list_items_by_id.fetch(position[:id].to_i).update!(priority: position[:priority], position: position[:position])
      end
    end

    head :no_content
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

  def list_item_params
    params.require(:list_item).permit(:name, :notes, :url, :price, :quantity, :priority, :visible)
  end

  def positions_params
    params.permit(positions: [ :id, :priority, :position ])
  end

  def valid_reorder_positions?(list, positions)
    return false unless positions.present?

    ids = positions.map { |position| position[:id].to_i }
    positions_by_priority = positions.group_by { |position| position[:priority] }.transform_values { |positions| positions.map { |position| position[:position].to_i } }

    ids.uniq.length == ids.length &&
      ids.sort == list.list_items.ids.sort &&
      positions_by_priority.keys.all? { |priority| ListItem.priorities.key?(priority) } &&
      positions_by_priority.values.all? { |positions| positions.sort == (0...positions.length).to_a }
  end
end
