import Http.Parse

open Http

/-- Read one request from a file and print `accept N` or `reject`. -/
def main : List String → IO UInt32
  | [] => do
    IO.eprintln "usage: http-tool FILE"
    return 2
  | path :: _ => do
    let data ← IO.FS.readBinFile path
    match parseRequest data.toList with
    | none =>
      IO.println "reject"
      return 0
    | some r =>
      IO.println s!"accept {r.body.length}"
      return 0
