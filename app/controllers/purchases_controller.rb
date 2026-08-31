class PurchasesController < ApplicationController
  def create
    list_item = find_list_item

    @list = list_item.list

    @purchase = list_item.purchases.build(purchase_params)

    @purchase.user = current_user

    authorize_purchase_create!

    ListItem.transaction do
      list_item.lock!

      unless @purchase.save
        return render partial: "purchases/form", locals: { list: @list, list_item: list_item, purchase: @purchase }, status: :unprocessable_entity
      end
    end

    render_list_items(status: :created)
  end

  def update
    @purchase = find_purchase

    list_item = @purchase.list_item

    @list = list_item.list

    authorize_purchase_update!

    ListItem.transaction do
      list_item.lock!

      unless @purchase.update(purchase_params)
        return render partial: "list_items/form", locals: { list: @list, list_item: list_item, purchase: @purchase }, status: :unprocessable_entity
      end
    end

    render_list_items
  end

  def destroy
    @purchase = find_purchase

    list_item = @purchase.list_item

    @list = list_item.list

    authorize_purchase_destroy!

    ListItem.transaction do
      list_item.lock!

      unless @purchase.destroy
        flash[:error] = t(".error")

        return render partial: "list_items/list_items", status: :unprocessable_entity
      end
    end

    render_list_items
  end

  def owner
    @owner ||= User.friendly.find(params[:user_id])
  end
  helper_method :owner

  private

  def authorize_purchase_create!
    raise ActiveRecord::RecordNotFound if @list.user == current_user
  end

  def authorize_purchase_destroy!
    purchaser_can_destroy = @purchase.user == current_user && !@purchase.revealed?

    owner_can_destroy = @list.user == current_user && @purchase.revealed?

    unless purchaser_can_destroy || owner_can_destroy
      raise ActiveRecord::RecordNotFound
    end
  end

  def authorize_purchase_update!
    unless @purchase.user == current_user && !@purchase.revealed?
      raise ActiveRecord::RecordNotFound
    end
  end

  def find_list
    owner.lists.publicly_visible.friendly.find(params[:list_id])
  end

  def find_list_item
    find_list.list_items.find(list_item_id_param)
  end

  def find_purchase
    find_list_item.purchases.find(params[:id])
  end

  def list_item_id_param
    params.require(:purchase).permit(:list_item_id)[:list_item_id]
  end

  def purchase_params
    params.require(:purchase).permit(:purchased_from, :notes, :price, :quantity, :reveal_at, :anonymous)
  end

  def render_list_items(status: :ok)
    @list_items = @list.list_items.visible_to(current_user).ordered.includes(:purchases)
    @list_items_by_priority = @list_items.group_by(&:priority)

    render partial: "list_items/list_items", status:
  end
end
