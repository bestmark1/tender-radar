import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

// Клиент для Server Components / Route Handlers.
// cookies() в Next 16 асинхронный — поэтому функция async.
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          // В Server Components запись cookie может бросать — это ок,
          // обновление сессии берёт на себя middleware.
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options),
            );
          } catch {
            // вызвано из Server Component — игнорируем
          }
        },
      },
    },
  );
}
