import { type NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/session";

// Next 16: корневой файл называется proxy.ts (бывший middleware.ts).
// Обновляет сессию Supabase и защищает приватные маршруты.
export async function proxy(request: NextRequest) {
  return await updateSession(request);
}

export const config = {
  matcher: [
    // Все пути, кроме статики и метафайлов.
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
