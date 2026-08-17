"""
vCRGlove Clinical Dashboard (Streamlit)
========================================
Run:  streamlit run dashboard.py

Reads live data from the FastAPI backend.
Configure BACKEND_URL and API_KEY in the sidebar or via environment variables:
  export VCR_BACKEND_URL=https://vcr-backend.uke.de/api
  export VCR_API_KEY=<your key>
"""

import os
import requests
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st

# ── Page config ───────────────────────────────────────────────────────────────

st.set_page_config(
    page_title="vCRGlove — Clinical Dashboard",
    page_icon="🧤",
    layout="wide",
)

# ── Sidebar: connection settings ──────────────────────────────────────────────

with st.sidebar:
    st.header("⚙️ Connection")
    backend_url = st.text_input(
        "Backend URL",
        value=os.getenv("VCR_BACKEND_URL", "http://localhost:8000"),
    )
    api_key = st.text_input(
        "API Key",
        value=os.getenv("VCR_API_KEY", ""),
        type="password",
    )
    st.divider()
    st.header("🔍 Filters")
    patient_filter = st.text_input("Patient ID (leave blank for all)")

HEADERS = {"Authorization": f"Bearer {api_key}"}
TASK_LABELS = {
    "3.4": "Finger Tapping",
    "3.5": "Hand Open/Close",
    "3.6": "Pronation/Supination",
}
CONTEXT_COLORS = {
    "baseline":    "#5b9bd5",
    "preStim":     "#ed7d31",
    "postStim":    "#70ad47",
    "unspecified": "#a5a5a5",
}

# ── Data loading ──────────────────────────────────────────────────────────────

@st.cache_data(ttl=30, show_spinner="Loading data from backend…")
def load_data(url: str, key: str, patient: str) -> pd.DataFrame:
    params = {"patient_id": patient} if patient else {}
    r = requests.get(f"{url}/sessions", headers={"Authorization": f"Bearer {key}"},
                     params=params, timeout=10)
    r.raise_for_status()
    df = pd.DataFrame(r.json())
    if df.empty:
        return df
    df["session_date"] = pd.to_datetime(df["session_date"])
    df["task_label"]   = df["task"].map(TASK_LABELS).fillna(df["task"])
    return df

# ── Load ──────────────────────────────────────────────────────────────────────

st.title("🧤 vCRGlove — Clinical Research Dashboard")

if not api_key:
    st.info("Enter the API key in the sidebar to connect.")
    st.stop()

try:
    df = load_data(backend_url, api_key, patient_filter)
except Exception as e:
    st.error(f"Cannot reach backend: {e}")
    st.stop()

if df.empty:
    st.warning("No data found. Record some sessions in the app first.")
    st.stop()

# ── KPI row ───────────────────────────────────────────────────────────────────

col1, col2, col3, col4 = st.columns(4)
col1.metric("Patients",  df["patient_id"].nunique())
col2.metric("Sessions",  df["session_id"].nunique())
col3.metric("Trials",    len(df))
col4.metric("Last upload", df["session_date"].max().strftime("%d.%m.%Y %H:%M"))

st.divider()

# ── Tab layout ────────────────────────────────────────────────────────────────

tab_trend, tab_prepost, tab_table, tab_export = st.tabs([
    "📈 Longitudinal Trends",
    "⚖️ Pre vs. Post",
    "📋 Data Table",
    "⬇️ Export",
])

# ── Tab 1: Longitudinal Trends ────────────────────────────────────────────────

with tab_trend:
    c1, c2, c3 = st.columns(3)
    selected_patient = c1.selectbox("Patient", sorted(df["patient_id"].unique()))
    selected_task    = c2.selectbox("Task",    sorted(df["task_label"].unique()))
    selected_metric  = c3.selectbox("Metric", [
        ("frequency_hz",              "Frequency (Hz)"),
        ("mean_amplitude",            "Mean Amplitude"),
        ("amplitude_decrement_slope", "Amplitude Decrement"),
        ("rhythm_cv",                 "Rhythm CV"),
        ("pause_count",               "Pause Count"),
        ("quality_index",             "Quality Index"),
    ], format_func=lambda x: x[1])
    metric_col, metric_label = selected_metric

    pdf = df[(df["patient_id"] == selected_patient) &
             (df["task_label"] == selected_task)].copy()

    if pdf.empty:
        st.info("No data for this combination.")
    else:
        for side, sdf in pdf.groupby("side"):
            fig = px.scatter(
                sdf, x="session_date", y=metric_col,
                color="context",
                color_discrete_map=CONTEXT_COLORS,
                trendline="lowess",
                labels={"session_date": "Date", metric_col: metric_label,
                        "context": "Context"},
                title=f"{selected_patient} · {selected_task} · {side} hand",
            )
            fig.update_traces(marker_size=10)
            fig.update_layout(height=380, legend_title="Context")
            st.plotly_chart(fig, use_container_width=True)

# ── Tab 2: Pre vs. Post ───────────────────────────────────────────────────────

with tab_prepost:
    pre_post = df[df["context"].isin(["preStim", "postStim"])].copy()
    if pre_post.empty:
        st.info("No preStim/postStim data available.")
    else:
        metric2 = st.selectbox("Metric", [
            ("frequency_hz",  "Frequency (Hz)"),
            ("mean_amplitude","Mean Amplitude"),
            ("rhythm_cv",     "Rhythm CV"),
            ("pause_count",   "Pause Count"),
        ], format_func=lambda x: x[1], key="pp_metric")
        m_col, m_label = metric2

        fig = px.box(
            pre_post, x="context", y=m_col,
            color="context",
            facet_col="task_label", facet_row="side",
            color_discrete_map=CONTEXT_COLORS,
            points="all",
            labels={"context": "", m_col: m_label},
            title=f"{m_label}: Pre vs. Post Stimulation",
            category_orders={"context": ["preStim", "postStim"]},
        )
        fig.update_layout(height=600, showlegend=False)
        st.plotly_chart(fig, use_container_width=True)

        # Wilcoxon table
        from scipy import stats
        rows = []
        for task, tdf in pre_post.groupby("task_label"):
            for side, sdf in tdf.groupby("side"):
                paired = sdf.pivot_table(
                    index="session_id", columns="context",
                    values=m_col, aggfunc="mean"
                ).dropna()
                if len(paired) >= 5:
                    _, p = stats.wilcoxon(paired["preStim"], paired["postStim"])
                    delta = (paired["postStim"] - paired["preStim"]).mean()
                    rows.append({"Task": task, "Side": side,
                                 "n (pairs)": len(paired),
                                 "Δ mean": f"{delta:+.3f}",
                                 "Wilcoxon p": f"{p:.3f}"})
        if rows:
            st.subheader("Statistical summary")
            st.dataframe(pd.DataFrame(rows), use_container_width=True)

# ── Tab 3: Data Table ─────────────────────────────────────────────────────────

with tab_table:
    show_cols = [
        "patient_id","session_date","context","task_label","side","source",
        "cycle_count","frequency_hz","mean_amplitude",
        "rhythm_cv","pause_count","quality_index",
    ]
    st.dataframe(
        df[show_cols].rename(columns={"task_label": "task"})
          .sort_values("session_date", ascending=False),
        use_container_width=True,
    )

# ── Tab 4: Export ─────────────────────────────────────────────────────────────

with tab_export:
    st.markdown("Download a CSV of all metrics directly from the backend.")
    params = f"?patient_id={patient_filter}" if patient_filter else ""
    csv_url = f"{backend_url}/export/metrics{params}"
    if st.button("⬇️ Download metrics.csv"):
        r = requests.get(csv_url, headers=HEADERS, timeout=30)
        if r.ok:
            st.download_button(
                "Save file", data=r.content,
                file_name="vcrglove_metrics.csv", mime="text/csv"
            )
        else:
            st.error(f"Download failed: {r.status_code}")

    st.divider()
    st.caption(f"Backend: `{backend_url}`  |  Data auto-refreshes every 30 s")
    if st.button("🔄 Refresh now"):
        st.cache_data.clear()
        st.rerun()
