
import joblib
import pandas as pd
import numpy as np
import re
import ipaddress
import tldextract
import traceback

from urllib.parse import urlparse
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sklearn.pipeline import Pipeline


# ==========================================
# KONFIGURASI FASTAPI
# ==========================================

app = FastAPI(
    title="PhishGuard Backend - URL Phishing Detection"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ==========================================
# MEMUAT MODEL
# ==========================================

MODEL_PATH = "model_urlphish_rf7.pkl"

try:
    model = joblib.load(MODEL_PATH)

    print("\n========== MODEL BERHASIL DIMUAT ==========")
    print("Jenis model:", type(model).__name__)

    if hasattr(model, "classes_"):
        print("Kelas model:", model.classes_)

    if hasattr(model, "estimators_"):
        print("Jumlah pohon:", len(model.estimators_))

    elif isinstance(model, Pipeline):
        print("Model menggunakan Pipeline.")

    print("===========================================\n")

except Exception as e:
    print("Gagal memuat model:", str(e))
    model = None


class URLRequest(BaseModel):
    url: str


# ==========================================
# MENGAMBIL RANDOM FOREST
# ==========================================

def ambil_random_forest(model_obj):

    if model_obj is None:
        return None

    # Jika model langsung berupa Random Forest
    if hasattr(model_obj, "estimators_"):
        return model_obj

    # Jika model berupa Pipeline
    if isinstance(model_obj, Pipeline):

        for _, step in reversed(model_obj.steps):

            if hasattr(step, "estimators_"):
                return step

    return None


# ==========================================
# MEMPERSIAPKAN INPUT UNTUK POHON
# ==========================================

def input_untuk_random_forest(model_obj, df):

    if not isinstance(model_obj, Pipeline):
        return df

    hasil = df.copy()

    # Transformasi mengikuti tahapan Pipeline
    for _, step in model_obj.steps[:-1]:

        if hasattr(step, "transform"):
            hasil = step.transform(hasil)

        elif hasattr(step, "predict"):
            break

    return hasil



# ==========================================
# VALIDASI STRUKTUR URL
# ==========================================

def validasi_url(url: str) -> bool:
    """
    Memastikan input memiliki struktur URL HTTP/HTTPS dan hostname valid.
    Validasi ini tidak melakukan DNS lookup, sehingga tidak menjamin
    domain benar-benar aktif/terdaftar.
    """
    from urllib.parse import urlsplit
    import socket

    value = str(url).strip()

    # URL kosong, terlalu panjang, atau mengandung whitespace/control char.
    if not value or len(value) > 2048:
        return False

    if any(ch.isspace() or ord(ch) < 32 or ord(ch) == 127 for ch in value):
        return False

    # Tolak karakter yang tidak valid/berisiko pada URL mentah.
    if any(ch in value for ch in '<>"{}|\\^`'):
        return False

    # Persentase harus diikuti dua digit heksadesimal.
    if re.search(r'%(?![0-9a-fA-F]{2})', value):
        return False

    # URL tanpa skema tetap boleh, misalnya google.com/login.
    candidate = value if re.match(r'^https?://', value, re.IGNORECASE) else 'https://' + value

    try:
        parsed = urlsplit(candidate)

        if parsed.scheme.lower() not in ("http", "https"):
            return False

        if not parsed.netloc or not parsed.hostname:
            return False

        # Memaksa pemeriksaan port agar port non-angka / di luar rentang ditolak.
        port = parsed.port
        if port is not None and not (1 <= port <= 65535):
            return False

        host = parsed.hostname.rstrip(".").lower()
        if not host or len(host) > 253:
            return False

        # Terima alamat IP valid (IPv4/IPv6).
        try:
            ipaddress.ip_address(host)
            return True
        except ValueError:
            pass

        # Normalisasi nama domain internasional (IDN) ke ASCII.
        try:
            host_ascii = host.encode("idna").decode("ascii")
        except (UnicodeError, ValueError):
            return False

        if len(host_ascii) > 253 or "." not in host_ascii:
            return False

        labels = host_ascii.split(".")
        if len(labels) < 2:
            return False

        label_pattern = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")

        for label in labels:
            if not label or len(label) > 63:
                return False
            if not label_pattern.fullmatch(label):
                return False

        # TLD harus berupa huruf 2-63 karakter atau punycode.
        tld = labels[-1]
        if not (
            re.fullmatch(r"[a-z]{2,63}", tld)
            or re.fullmatch(r"xn--[a-z0-9-]{2,}", tld)
        ):
            return False

        return True

    except (ValueError, UnicodeError, socket.error):
        return False


# ==========================================
# EKSTRAKSI 42 FITUR URL
# ==========================================

def ekstrak_fitur_baru(url):

    url = str(url).strip()

    if "://" not in url:
        url_parse = "http://" + url
    else:
        url_parse = url

    p = urlparse(url_parse)
    host = (p.hostname or "").lower()
    path = p.path or ""

    def words(s):
        return [
            w for w in re.split(r"[^a-zA-Z0-9]+", s)
            if w
        ]

    def shortest(ws):
        return min(map(len, ws), default=0)

    def longest(ws):
        return max(map(len, ws), default=0)

    def avg(ws):
        return (
            float(np.mean([len(w) for w in ws]))
            if ws else 0.0
        )

    try:
        ipaddress.ip_address(host)
        is_ip = 1
    except ValueError:
        is_ip = 0

    def hitung_nb_subdomains(url):

        url = str(url).strip()

        if not url or url.lower() == "nan":
            return 0

        if "://" not in url:
            url = "http://" + url

        hasil = tldextract.extract(url)

        if not hasil.subdomain:
            return 0

        return len(hasil.subdomain.split("."))

    rw = words(url)
    hw = words(host)
    pw = words(path)

    digit_url = sum(c.isdigit() for c in url)
    digit_host = sum(c.isdigit() for c in host)

    try:
        has_port = int(p.port is not None)
    except ValueError:
        has_port = 0

    fitur = {
        "length_url": len(url),
        "length_hostname": len(host),
        "ip": is_ip,
        "nb_dots": url.count("."),
        "nb_hyphens": url.count("-"),
        "nb_at": url.count("@"),
        "nb_qm": url.count("?"),
        "nb_and": url.count("&"),
        "nb_eq": url.count("="),
        "nb_underscore": url.count("_"),
        "nb_tilde": url.count("~"),
        "nb_percent": url.count("%"),
        "nb_slash": url.count("/"),
        "nb_star": url.count("*"),
        "nb_colon": url.count(":"),
        "nb_comma": url.count(","),
        "nb_semicolumn": url.count(";"),
        "nb_dollar": url.count("$"),
        "nb_space": url.count(" "),
        "nb_www": url.lower().count("www"),
        "nb_com": max(
            0,
            url.lower().count("com") - int("com" in host)
        ),
        "nb_dslash": int(
            "//" in url.split("://", 1)[-1]
        ),
        "http_in_path": int(
            "http" in path.lower()
        ),
        "https_token": int(
            p.scheme.lower() == "http"
        ),
        "ratio_digits_url": (
            digit_url / len(url) if url else 0
        ),
        "ratio_digits_host": (
            digit_host / len(host) if host else 0
        ),
        "punycode": int("xn--" in host),
        "port": has_port,
        "nb_subdomains": hitung_nb_subdomains(url),
        "prefix_suffix": int("-" in host),
        "path_extension": int(
            bool(re.search(r"\.[a-zA-Z0-9]{1,10}$", path))
        ),
        "length_words_raw": len(rw),
        "char_repeat": sum(
            len(m.group()) - 1
            for m in re.finditer(r"(.)\1+", url)
        ),
        "shortest_words_raw": shortest(rw),
        "shortest_word_host": shortest(hw),
        "shortest_word_path": shortest(pw),
        "longest_words_raw": longest(rw),
        "longest_word_host": longest(hw),
        "longest_word_path": longest(pw),
        "avg_words_raw": avg(rw),
        "avg_word_host": avg(hw),
        "avg_word_path": avg(pw)
    }

    return fitur


# ==========================================
# MENCARI INDEKS KELAS PHISHING
# ==========================================

def cari_indeks_phishing(model_obj):

    if not hasattr(model_obj, "classes_"):
        raise ValueError(
            "Model tidak memiliki informasi classes_."
        )

    classes = list(model_obj.classes_)

    for idx, cls in enumerate(classes):

        cls_str = str(cls).lower()

        if cls_str in [
            "1",
            "1.0",
            "phishing",
            "bad",
            "malicious",
            "true"
        ]:
            return idx

    raise ValueError(
        f"Kelas Phishing tidak ditemukan. Kelas model: {classes}"
    )


# ==========================================
# MENYESUAIKAN FITUR DENGAN MODEL
# ==========================================

def sesuaikan_fitur(model_obj, df):

    expected_cols = getattr(
        model_obj,
        "feature_names_in_",
        None
    )

    if expected_cols is None:

        rf_model = ambil_random_forest(model_obj)

        if not isinstance(model_obj, Pipeline) and rf_model is not None:
            expected_cols = getattr(
                rf_model,
                "feature_names_in_",
                None
            )

    if expected_cols is not None:

        for col in expected_cols:

            if col not in df.columns:
                df[col] = 0

        df = df.reindex(
            columns=expected_cols,
            fill_value=0
        )

    return df


# ==========================================
# ENDPOINT DETEKSI URL
# ==========================================

@app.post("/predict")
def predict_url(request: URLRequest):

    if model is None:
        raise HTTPException(
            status_code=500,
            detail="Model Machine Learning belum dimuat."
        )

    try:

        url_input = request.url.strip()

        if not url_input:
            raise HTTPException(
                status_code=422,
                detail="URL tidak boleh kosong."
            )

        # VALIDASI STRUKTUR URL SEBELUM MASUK KE EKSTRAKSI FITUR/MODEL
        if not validasi_url(url_input):
            raise HTTPException(
                status_code=422,
                detail=(
                    "URL tidak valid. Masukkan alamat website dengan "
                    "domain yang benar, contoh: https://google.com"
                )
            )

        # EKSTRAKSI FITUR
        fitur_dict = ekstrak_fitur_baru(url_input)

        df_features = pd.DataFrame([fitur_dict])

        # MENYESUAIKAN KOLOM DENGAN MODEL
        df_features = sesuaikan_fitur(
            model,
            df_features
        )

        # PREDIKSI MODEL
        prediction = model.predict(df_features)[0]

        # MENCARI KELAS PHISHING
        phish_index = cari_indeks_phishing(model)

        phishing_class = model.classes_[phish_index]

        # ==================================
        # PROBABILITAS
        # ==================================

        if hasattr(model, "predict_proba"):

            proba = model.predict_proba(df_features)[0]

            prob_phishing = float(
                proba[phish_index]
            )

        else:

            prob_phishing = (
                1.0
                if prediction == phishing_class
                else 0.0
            )

        prob_legitimate = 1.0 - prob_phishing

        # ==================================
        # VOTING RANDOM FOREST
        # ==================================

        rf_model = ambil_random_forest(model)

        tree_votes = 0
        total_trees = 0

        if rf_model is not None:

            total_trees = len(rf_model.estimators_)

            # Jika menggunakan Pipeline, pohon menerima
            # hasil transformasi dari tahapan sebelumnya.
            tree_input = input_untuk_random_forest(
                model,
                df_features
            )

            for tree in rf_model.estimators_:

                tree_prediction = tree.predict(tree_input)[0]

                # Random Forest sklearn menyimpan kelas
                # pohon dalam bentuk indeks internal.
                if int(tree_prediction) == phish_index:
                    tree_votes += 1

        # ==================================
        # HASIL DETEKSI
        # ==================================

        level = (
            "phishing"
            if prob_phishing >= 0.5
            else "safe"
        )

        # ==================================
        # DATA FITUR UNTUK FLUTTER
        # ==================================

        features_list = []

        for k, v in fitur_dict.items():

            features_list.append({
                "name": k,
                "value": str(v),
                "tendency": (
                    "legitimate"
                    if level == "safe"
                    else "phishing"
                )
            })

        # ==================================
        # LOG TERMINAL
        # ==================================

        print("\n========== HASIL DETEKSI ==========")
        print(f"URL              : {url_input}")
        print(f"Prediksi         : {prediction}")
        print(f"Prob Phishing    : {prob_phishing:.4f}")
        print(f"Prob Legitimate  : {prob_legitimate:.4f}")

        if total_trees > 0:

            print(
                f"Pohon Phishing   : {tree_votes}/{total_trees}"
            )

            print(
                f"Pohon Legitimate : {total_trees - tree_votes}"
            )

        else:

            print("Voting pohon     : Tidak tersedia pada model ini")

        print("===================================\n")

        # ==================================
        # RESPONS JSON UNTUK FLUTTER
        # ==================================

        return {
            "url": url_input,
            "level": level,
            "probPhishing": prob_phishing,
            "probLegitimate": prob_legitimate,
            "treeVotes": tree_votes,
            "totalTrees": total_trees,
            "featureCount": len(fitur_dict),
            "features": features_list
        }

    except HTTPException:
        raise

    except Exception as e:

        traceback.print_exc()

        raise HTTPException(
            status_code=500,
            detail=str(e)
        )


# ==========================================
# ENDPOINT HOME
# ==========================================

@app.get("/")
def home():

    return {
        "message": "PhishGuard Backend Running!"
    }
