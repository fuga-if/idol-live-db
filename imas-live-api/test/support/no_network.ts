// テストから外部 (Apple / Google / CloudKit / GitHub) へ通信させない。
// 外部の応答が要るテストは fetchMock.get(origin).intercept(...) で個別に返す。
//
// ⚠️ fetchMock はテストファイルごとに初期化されるので、setup ファイルの本体で有効にしても
//    消える。各ファイルの beforeAll で有効にする。
import { fetchMock } from "cloudflare:test";
import { beforeAll } from "vitest";

beforeAll(() => {
  fetchMock.activate();
  fetchMock.disableNetConnect();
});
