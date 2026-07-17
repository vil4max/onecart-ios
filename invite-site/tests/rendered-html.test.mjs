import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const validToken = "7a4e7a84-38a1-4e6b-8e4c-6a5d0d18b0c2";

async function render(path = "/") {
  const workerURL = new URL("../dist/server/index.js", import.meta.url);
  workerURL.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerURL.href);

  return worker.fetch(
    new Request(`http://localhost${path}`, {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("renders a valid OneCart invitation with a native deep link", async () => {
  const response = await render(`/?token=${validToken}`);

  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<html[^>]+lang="ru"/i);
  assert.match(html, /<title>Приглашение в OneCart<\/title>/i);
  assert.match(html, /Вас пригласили в OneCart/);
  assert.match(html, /Открыть OneCart/);
  assert.match(html, new RegExp(`onecart://invite/${validToken}`, "i"));
  assert.doesNotMatch(html, /supabase\.co|codex-preview/i);
});

test("rejects missing and malformed invitation tokens", async () => {
  for (const path of ["/", "/?token=not-a-token"]) {
    const response = await render(path);
    const html = await response.text();

    assert.equal(response.status, 200);
    assert.match(html, /Ссылка недействительна/);
    assert.doesNotMatch(html, /onecart:\/\/invite\//i);
  }
});

test("keeps the page self-contained and removes starter UI", async () => {
  const [page, opener, layout, packageJSON] = await Promise.all([
    readFile(new URL("app/page.tsx", root), "utf8"),
    readFile(new URL("app/OpenInOneCart.tsx", root), "utf8"),
    readFile(new URL("app/layout.tsx", root), "utf8"),
    readFile(new URL("package.json", root), "utf8"),
  ]);

  assert.match(opener, /window\.location\.assign\(appURL\)/);
  assert.match(layout, /index:\s*false/);
  assert.doesNotMatch(page, /https?:\/\//);
  assert.doesNotMatch(packageJSON, /react-loading-skeleton/);
  await assert.rejects(access(new URL("app/_sites-preview", root)));
});
