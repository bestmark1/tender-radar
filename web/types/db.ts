// Типы БД под схему миграции 0001_init.sql.
// (Вручную; позже можно заменить на `supabase gen types typescript`.)

export type RadarLaw = "44" | "223" | "both";
export type MatchStatus = "new" | "interested" | "hidden";

export interface RadarRow {
  id: string;
  user_id: string;
  name: string;
  regions: string[];
  okpd_prefixes: string[];
  keywords_include: string[];
  keywords_exclude: string[];
  price_min: number | null;
  price_max: number | null;
  law: RadarLaw;
  reminder_days: number;
  is_active: boolean;
  created_at: string;
}

export type RadarInsert = Omit<RadarRow, "id" | "created_at">;
export type RadarUpdate = Partial<Omit<RadarRow, "id" | "user_id" | "created_at">>;

export interface TenderRow {
  id: string;
  reg_number: string;
  version: number;
  title: string | null;
  customer: string | null;
  region: string | null;
  okpd: string | null;
  price: number | null;
  published_at: string | null;
  submission_deadline: string | null;
  eis_url: string | null;
  law: string | null;
  raw: unknown | null;
  created_at: string;
}

export interface MatchRow {
  id: string;
  tender_id: string;
  radar_id: string;
  user_id: string;
  status: MatchStatus;
  notified: boolean;
  reminded: boolean;
  created_at: string;
}

// Форма Database должна совпадать с тем, что ожидает supabase-js (GenericSchema),
// иначе типизация операций схлопывается в never. Поэтому Views/Functions/Enums/
// CompositeTypes и Relationships присутствуют (пусть и пустые).
export interface Database {
  public: {
    Tables: {
      radars: {
        Row: RadarRow;
        Insert: RadarInsert;
        Update: RadarUpdate;
        Relationships: [];
      };
      tenders: {
        Row: TenderRow;
        Insert: TenderRow;
        Update: Partial<TenderRow>;
        Relationships: [];
      };
      matches: {
        Row: MatchRow;
        Insert: MatchRow;
        Update: Pick<MatchRow, "status">;
        Relationships: [];
      };
    };
    Views: { [_ in never]: never };
    Functions: { [_ in never]: never };
    Enums: { [_ in never]: never };
    CompositeTypes: { [_ in never]: never };
  };
}
