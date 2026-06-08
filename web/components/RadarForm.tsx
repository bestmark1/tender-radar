"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { validateRadar } from "@/lib/radarValidation";
import type { RadarLaw } from "@/lib/radarValidation";
import type { RadarRow } from "@/types/db";

function splitCsv(s: string): string[] {
  return s
    .split(",")
    .map((x) => x.trim())
    .filter(Boolean);
}

const field: React.CSSProperties = { width: "100%", padding: 8, marginBottom: 10 };
const label: React.CSSProperties = { display: "block", fontWeight: 600, marginBottom: 4 };

export default function RadarForm({ initial }: { initial?: RadarRow }) {
  const router = useRouter();
  const [name, setName] = useState(initial?.name ?? "");
  const [regions, setRegions] = useState((initial?.regions ?? ["77", "50"]).join(", "));
  const [okpd, setOkpd] = useState((initial?.okpd_prefixes ?? ["81.2"]).join(", "));
  const [kwInclude, setKwInclude] = useState((initial?.keywords_include ?? []).join(", "));
  const [kwExclude, setKwExclude] = useState((initial?.keywords_exclude ?? []).join(", "));
  const [priceMin, setPriceMin] = useState(initial?.price_min?.toString() ?? "");
  const [priceMax, setPriceMax] = useState(initial?.price_max?.toString() ?? "");
  const [law, setLaw] = useState<RadarLaw>(initial?.law ?? "44");
  const [reminderDays, setReminderDays] = useState((initial?.reminder_days ?? 2).toString());
  const [errors, setErrors] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const input = {
      name,
      regions: splitCsv(regions),
      okpdPrefixes: splitCsv(okpd),
      keywordsInclude: splitCsv(kwInclude),
      keywordsExclude: splitCsv(kwExclude),
      priceMin: priceMin === "" ? null : Number(priceMin),
      priceMax: priceMax === "" ? null : Number(priceMax),
      law,
      reminderDays: Number(reminderDays) || 2,
    };

    const result = validateRadar(input);
    if (!result.valid) {
      setErrors(result.errors);
      return;
    }
    setErrors([]);
    setSaving(true);

    const supabase = createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) {
      setErrors(["Сессия истекла, войдите снова"]);
      setSaving(false);
      return;
    }

    const payload = {
      user_id: user.id,
      name: input.name,
      regions: input.regions,
      okpd_prefixes: input.okpdPrefixes,
      keywords_include: input.keywordsInclude,
      keywords_exclude: input.keywordsExclude,
      price_min: input.priceMin,
      price_max: input.priceMax,
      law: input.law,
      reminder_days: input.reminderDays,
      is_active: initial?.is_active ?? true,
    };

    const res = initial
      ? await supabase.from("radars").update(payload).eq("id", initial.id)
      : await supabase.from("radars").insert(payload);

    setSaving(false);
    if (res.error) {
      setErrors([res.error.message]);
      return;
    }
    router.push("/radars");
    router.refresh();
  }

  return (
    <form onSubmit={handleSubmit} style={{ maxWidth: 520 }}>
      <label style={label}>Название</label>
      <input style={field} value={name} onChange={(e) => setName(e.target.value)} placeholder="Клининг МСК" />

      <label style={label}>Регионы (коды через запятую)</label>
      <input style={field} value={regions} onChange={(e) => setRegions(e.target.value)} placeholder="77, 50" />

      <label style={label}>ОКПД2 (префиксы через запятую)</label>
      <input style={field} value={okpd} onChange={(e) => setOkpd(e.target.value)} placeholder="81.2" />

      <label style={label}>Ключевые слова — включить</label>
      <input style={field} value={kwInclude} onChange={(e) => setKwInclude(e.target.value)} placeholder="уборка, клининг" />

      <label style={label}>Ключевые слова — исключить</label>
      <input style={field} value={kwExclude} onChange={(e) => setKwExclude(e.target.value)} placeholder="вывоз мусора" />

      <label style={label}>НМЦК, ₽ (мин / макс)</label>
      <div style={{ display: "flex", gap: 8 }}>
        <input style={field} type="number" value={priceMin} onChange={(e) => setPriceMin(e.target.value)} placeholder="мин" />
        <input style={field} type="number" value={priceMax} onChange={(e) => setPriceMax(e.target.value)} placeholder="макс" />
      </div>

      <label style={label}>Закон</label>
      <select style={field} value={law} onChange={(e) => setLaw(e.target.value as RadarLaw)}>
        <option value="44">44-ФЗ</option>
        <option value="223">223-ФЗ</option>
        <option value="both">Оба</option>
      </select>

      <label style={label}>Напоминать за (дней до дедлайна)</label>
      <input style={field} type="number" value={reminderDays} onChange={(e) => setReminderDays(e.target.value)} />

      {errors.length > 0 && (
        <ul style={{ color: "crimson" }}>
          {errors.map((err, i) => (
            <li key={i}>{err}</li>
          ))}
        </ul>
      )}

      <button type="submit" disabled={saving} style={{ padding: "8px 16px" }}>
        {saving ? "Сохранение…" : initial ? "Сохранить" : "Создать радар"}
      </button>
    </form>
  );
}
