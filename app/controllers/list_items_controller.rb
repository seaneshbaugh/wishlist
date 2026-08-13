class ListItemsController < ApplicationController
  def create
    @list = find_list

    @list_item = @list.list_items.build(list_item_params)

    if @list_item.save
      render partial: "list_items/create", status: :created
    else
      render partial: "list_items/form", status: :unprocessable_entity
    end
  end

  def update
    @list_item = find_list_item

    if @list_item.update(list_params)
      render partial: "list_items/update", status: :ok
    else
      render partial: "list_items/form", status: :unprocessable_entity
    end
  end

  def destroy
    @list_item = find_list_item

    if @list_item.destroy
      render partial: "list_items/destroy", status: :ok
    else
      render partial: "list_items/error", status: :unprocessable_entity
    end
  end

  def reorder
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
    params.permition(positions: [ :id, :priority, :position ])
  end

  def valid_reorder_positions?(positions)
    return fasle unless positions.present?

    ids = positions.map { |position| position[:id].to_i }
    positions_values = positions.map { |position| position[:position].to_i }

    ids.uniq.length == ids.length &&
      ids.sort == current_user.lists.id.sort &&
      positions_values.sort == (0...ids.length).to_a
  end
end
