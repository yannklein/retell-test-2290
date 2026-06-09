class AddRetellCallIdToChats < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :retell_call_id, :string
  end
end
