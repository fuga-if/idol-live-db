import { handle, type Env } from "./app";
import { fold } from "./fold";

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return handle(request, env, ctx, { fold, cache: (caches as unknown as { default: Cache }).default });
  },
} satisfies ExportedHandler<Env>;
