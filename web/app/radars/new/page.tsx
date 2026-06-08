import RadarForm from "@/components/RadarForm";

export default function NewRadarPage() {
  return (
    <main style={{ maxWidth: 600, margin: "2rem auto", padding: "0 1rem", fontFamily: "system-ui, sans-serif" }}>
      <h1>Новый радар</h1>
      <RadarForm />
    </main>
  );
}
