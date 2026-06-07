import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Тендер-радар",
  description: "Мониторинг госзакупок 44-ФЗ для поставщиков",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="ru">
      <body>{children}</body>
    </html>
  );
}
