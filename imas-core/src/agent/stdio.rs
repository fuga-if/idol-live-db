//! stdio トランスポート (行区切り JSON-RPC)。MCP クライアントはこれで繋ぐ。
//!
//! 1 行 = 1 JSON-RPC メッセージ・改行終端。**stdout には JSON-RPC 以外を 1 バイトも
//! 書かない** — MCP クライアントは stdout をそのままメッセージ境界として読むので、
//! ログや診断文言を混ぜると黙ってプロトコルが壊れる。ログは必ず stderr。
//!
//! 行が JSON として読めない場合は Parse error (`-32700`) を返して**接続は切らない**
//! (1 行の事故で残りのセッションまで落とす理由が無い)。同じ理由で:
//! - 行が非 UTF-8 でも `read_line` (String 前提) のように `Err` で丸ごと落とさず、
//!   `String::from_utf8_lossy` で読めるところだけ読んで Parse error にする。
//! - 1 行が異常に長いとき ([`MAX_LINE_BYTES`] 超) はメモリを際限なく食う前に打ち切り、
//!   Parse error にして次の行から再開する。

use super::Ctx;
use crate::domain::snapshot::Snapshot;
use serde_json::{json, Value};
use std::io::{self, BufRead, Write};

/// 1 行の上限。MCP の 1 メッセージがここまで大きくなることは通常無い
/// (`tools/call` の引数が巨大でもこの桁には収まる) ので、異常系の打ち切り用。
const MAX_LINE_BYTES: usize = 8 * 1024 * 1024;

/// 1 行分の読み取り結果。
enum LineRead {
    /// 入力が終わった (EOF)。
    Eof,
    /// 改行までの生バイト列 (改行は含まない)。
    Line(Vec<u8>),
    /// [`MAX_LINE_BYTES`] を超えたので打ち切った (改行までは読み捨てて同期を取り直した)。
    TooLong,
}

/// 標準入力が閉じる (EOF) まで応答し続ける。
pub fn serve(ctx: &Ctx, snap: &Snapshot) -> io::Result<()> {
    let stdin = io::stdin();
    let mut reader = io::BufReader::new(stdin.lock());
    let stdout = io::stdout();
    let mut writer = stdout.lock();

    loop {
        let response = match read_bounded_line(&mut reader, MAX_LINE_BYTES)? {
            LineRead::Eof => break,
            LineRead::TooLong => Some(json!({
                "jsonrpc": "2.0",
                "id": Value::Null,
                "error": {
                    "code": -32700,
                    "message": format!("Parse error: 1 行が {MAX_LINE_BYTES} バイトを超えています"),
                },
            })),
            LineRead::Line(bytes) => {
                // 非 UTF-8 が混ざっていても丸ごと捨てずに読めるところで判定する
                // (どのみち直後の JSON パースで弾かれるので、可逆性は求めない)。
                let text = String::from_utf8_lossy(&bytes);
                let trimmed = text.trim();
                if trimmed.is_empty() {
                    // 空行は「メッセージ 0 件」として無視する (改行の連投程度で切断しない)。
                    continue;
                }
                match serde_json::from_str::<Value>(trimmed) {
                    Ok(request) => super::mcp::handle(ctx, snap, &request),
                    Err(e) => Some(json!({
                        "jsonrpc": "2.0",
                        "id": Value::Null,
                        "error": { "code": -32700, "message": format!("Parse error: {e}") },
                    })),
                }
            }
        };

        if let Some(response) = response {
            writeln!(writer, "{}", serde_json::to_string(&response)?)?;
            writer.flush()?;
        }
    }
    Ok(())
}

/// `read_line` 相当だが、非 UTF-8 で丸ごと `Err` にしない (バイト列のまま返す) のと、
/// `limit` を超える行でプロセスのメモリを際限なく伸ばさないことの 2 点が違う。
///
/// 上限超過時は、蓄積は `limit` で止めつつも改行が来るまで読み捨てを続ける —
/// そうしないと次の `fill_buf` が「長い行の続き」を新しい行の先頭と誤認して
/// パースし、行境界がずれたまま壊れ続ける。
fn read_bounded_line<R: BufRead>(reader: &mut R, limit: usize) -> io::Result<LineRead> {
    let mut buf = Vec::new();
    let mut truncated = false;
    loop {
        let available = reader.fill_buf()?;
        if available.is_empty() {
            return Ok(if buf.is_empty() && !truncated {
                LineRead::Eof
            } else if truncated {
                LineRead::TooLong
            } else {
                LineRead::Line(buf)
            });
        }
        if let Some(pos) = available.iter().position(|&b| b == b'\n') {
            if !truncated && buf.len() + pos <= limit {
                buf.extend_from_slice(&available[..pos]);
            } else {
                truncated = true;
            }
            reader.consume(pos + 1);
            return Ok(if truncated { LineRead::TooLong } else { LineRead::Line(buf) });
        }
        let n = available.len();
        if !truncated {
            if buf.len() + n > limit {
                truncated = true;
            } else {
                buf.extend_from_slice(available);
            }
        }
        reader.consume(n);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn read_bounded_lineは改行無しの末尾行も拾う() {
        let mut cur = Cursor::new(b"tail-no-newline".to_vec());
        assert!(matches!(
            read_bounded_line(&mut cur, 1024).unwrap(),
            LineRead::Line(b) if b == b"tail-no-newline"
        ));
        assert!(matches!(read_bounded_line(&mut cur, 1024).unwrap(), LineRead::Eof));
    }

    #[test]
    fn read_bounded_lineは非utf8でもバイト列のまま返す() {
        let mut cur = Cursor::new(vec![0xff, 0xfe, b'\n']);
        match read_bounded_line(&mut cur, 1024).unwrap() {
            LineRead::Line(b) => assert_eq!(b, vec![0xff, 0xfe]),
            _ => panic!("Line を期待した"),
        }
    }

    #[test]
    fn read_bounded_lineは上限超過で打ち切り_次の行から再開する() {
        let mut cur = Cursor::new(b"aaaaaaaaaa\nshort\n".to_vec());
        assert!(matches!(read_bounded_line(&mut cur, 5).unwrap(), LineRead::TooLong));
        // 打ち切った行の残り (改行まで) は読み捨てられ、次の行はずれずに読める。
        assert!(matches!(
            read_bounded_line(&mut cur, 5).unwrap(),
            LineRead::Line(b) if b == b"short"
        ));
    }
}
