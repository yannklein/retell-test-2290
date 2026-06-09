class MessagesController < ApplicationController
  def create
    @chat = Chat.find(params[:chat_id])
    @message = Message.new(message_params)
    @message.chat = @chat
    if @message.save
      redirect_to chat_path(@chat)
    end
  end

  private

  def message_params
    params.require(:message).permit(:content)
  end
end
