// Валидация радара — US-1.4.
// Чистая функция (без зависимостей от БД/UI), чтобы покрыть тестами критерий приёмки:
// нельзя сохранить радар без хотя бы одного региона и хотя бы одного критерия фильтрации.

export type RadarLaw = "44" | "223" | "both";

export interface RadarInput {
  name: string;
  regions: string[];
  okpdPrefixes: string[];
  keywordsInclude: string[];
  keywordsExclude: string[];
  priceMin: number | null;
  priceMax: number | null;
  law: RadarLaw;
  reminderDays: number;
}

export interface ValidationResult {
  valid: boolean;
  errors: string[];
}

export function validateRadar(input: RadarInput): ValidationResult {
  const errors: string[] = [];

  if (!input.name || input.name.trim().length === 0) {
    errors.push("Укажите название радара");
  }

  if (!input.regions || input.regions.length === 0) {
    errors.push("Выберите хотя бы один регион");
  }

  const hasFilter =
    input.okpdPrefixes.length > 0 ||
    input.keywordsInclude.length > 0 ||
    input.priceMin !== null ||
    input.priceMax !== null;

  if (!hasFilter) {
    errors.push(
      "Задайте хотя бы один критерий фильтрации (ОКПД2, ключевое слово или диапазон цены)",
    );
  }

  if (
    input.priceMin !== null &&
    input.priceMax !== null &&
    input.priceMin > input.priceMax
  ) {
    errors.push("Минимальная цена не может быть больше максимальной");
  }

  if (!["44", "223", "both"].includes(input.law)) {
    errors.push("Некорректное значение закона");
  }

  return { valid: errors.length === 0, errors };
}
