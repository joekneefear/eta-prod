use std::io::{Write, Result as IoResult, Error as IoError, ErrorKind};
use bytes::Bytes;
use tokio::sync::mpsc::Sender as TokioSender;

// --- Output Pipe: Write -> Tokio Channel ---

pub struct ChannelWriter {
    sender: TokioSender<IoResult<Bytes>>,
}

impl ChannelWriter {
    pub fn new(sender: TokioSender<IoResult<Bytes>>) -> Self {
        Self { sender }
    }
}

impl Write for ChannelWriter {
    fn write(&mut self, buf: &[u8]) -> IoResult<usize> {
        let bytes = Bytes::copy_from_slice(buf);
        // We use blocking send because this runs in a blocking thread
        match self.sender.blocking_send(Ok(bytes)) {
            Ok(_) => Ok(buf.len()),
            Err(_) => Err(IoError::new(ErrorKind::BrokenPipe, "Output channel closed")),
        }
    }

    fn flush(&mut self) -> IoResult<()> {
        Ok(())
    }
}
