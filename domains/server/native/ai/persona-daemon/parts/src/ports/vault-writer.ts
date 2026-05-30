export interface InboxCaptureArgs {
  content: string;
  source: string;
  conversationId?: string;
  tags?: string[];
}

export interface InboxCaptureResult {
  savedPath: string;
}

export interface VaultWriterPort {
  captureInbox(args: InboxCaptureArgs): Promise<InboxCaptureResult>;
}
