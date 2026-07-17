import Image from "next/image";
import { OpenInOneCart } from "./OpenInOneCart";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type InvitePageProps = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function InvitePage({ searchParams }: InvitePageProps) {
  const params = await searchParams;
  const tokenValue = params.token;
  const token = (Array.isArray(tokenValue) ? tokenValue[0] : tokenValue)?.trim();
  const isValid = token !== undefined && uuidPattern.test(token);

  return (
    <main className="invite-shell">
      <div className="ambient ambient-left" aria-hidden="true" />
      <div className="ambient ambient-right" aria-hidden="true" />

      <section className="invite-card" aria-labelledby="invite-title">
        <div className="brand-lockup" aria-label="OneCart">
          <Image
            className="brand-mark"
            src="/onecart-mark.svg"
            alt=""
            width="52"
            height="52"
            priority
          />
          <span>OneCart</span>
        </div>

        {isValid ? (
          <>
            <p className="eyebrow">Семейный список покупок</p>
            <h1 id="invite-title">Вас пригласили в OneCart</h1>
            <p className="invite-copy">
              Откройте приложение, войдите или зарегистрируйтесь и подтвердите
              присоединение к семье.
            </p>

            <OpenInOneCart
              appURL={`onecart://invite/${encodeURIComponent(token.toLowerCase())}`}
            />

            <p className="helper-copy">
              Если приложение не открылось автоматически, нажмите кнопку ещё
              раз. Приглашение можно принять только один раз.
            </p>
          </>
        ) : (
          <div className="invalid-state" role="alert">
            <p className="eyebrow">Приглашение OneCart</p>
            <h1 id="invite-title">Ссылка недействительна</h1>
            <p className="invite-copy">
              Попросите владельца семьи отправить новое приглашение из
              приложения OneCart.
            </p>
          </div>
        )}
      </section>

      <p className="privacy-note">Безопасное приглашение · OneCart</p>
    </main>
  );
}
