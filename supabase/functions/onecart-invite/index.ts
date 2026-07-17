declare const Deno: {
  serve(handler: (request: Request) => Response | Promise<Response>): void;
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve((request: Request) => {
  const url = new URL(request.url);
  const token = url.searchParams.get("token")?.trim() ?? "";

  if (
    (request.method !== "GET" && request.method !== "HEAD") ||
    !uuidPattern.test(token)
  ) {
    return new Response("Некорректная ссылка-приглашение OneCart.", {
      status: 400,
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "no-referrer",
      },
    });
  }

  const appURL = `onecart://invite/${encodeURIComponent(token.toLowerCase())}`;

  return new Response(null, {
    status: 302,
    headers: {
      Location: appURL,
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
    },
  });
});
