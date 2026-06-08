import { createBrowserClient } from "@supabase/ssr";

// Клиент для Client Components (браузер).
// Без дженерик-схемы: типобезопасность обеспечиваем на своей границе
// (типы RowtRow из @/types/db + явные касты). См. TD-8.
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
