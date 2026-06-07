import { describe, it, expect } from "vitest";
import { validateRadar, type RadarInput } from "../lib/radarValidation";

function base(): RadarInput {
  return {
    name: "Клининг МСК",
    regions: ["77", "50"],
    okpdPrefixes: ["81.2"],
    keywordsInclude: [],
    keywordsExclude: [],
    priceMin: null,
    priceMax: null,
    law: "44",
    reminderDays: 2,
  };
}

describe("validateRadar — US-1.4", () => {
  it("валиден при регионе + ОКПД2", () => {
    expect(validateRadar(base()).valid).toBe(true);
  });

  it("невалиден без региона (AC-1.4)", () => {
    const r = validateRadar({ ...base(), regions: [] });
    expect(r.valid).toBe(false);
    expect(r.errors.some((e) => e.includes("регион"))).toBe(true);
  });

  it("невалиден без единого критерия фильтрации (AC-1.4)", () => {
    const r = validateRadar({
      ...base(),
      okpdPrefixes: [],
      keywordsInclude: [],
      priceMin: null,
      priceMax: null,
    });
    expect(r.valid).toBe(false);
    expect(r.errors.some((e) => e.includes("критерий"))).toBe(true);
  });

  it("валиден, если критерий — только ключевое слово", () => {
    const r = validateRadar({
      ...base(),
      okpdPrefixes: [],
      keywordsInclude: ["уборка"],
    });
    expect(r.valid).toBe(true);
  });

  it("валиден, если критерий — только диапазон цены", () => {
    const r = validateRadar({
      ...base(),
      okpdPrefixes: [],
      priceMin: 100000,
      priceMax: 500000,
    });
    expect(r.valid).toBe(true);
  });

  it("невалиден без названия", () => {
    const r = validateRadar({ ...base(), name: "   " });
    expect(r.valid).toBe(false);
  });

  it("невалиден, если priceMin > priceMax", () => {
    const r = validateRadar({ ...base(), priceMin: 900000, priceMax: 100000 });
    expect(r.valid).toBe(false);
  });
});
