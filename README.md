# Ezber

İngilizcenin en sık kullanılan 2800 kelimesini telefonda kalıcı olarak ezberleten Android uygulaması. Hesap ve sunucu yok, uygulamanın internet izni de yok; ilerleme yalnızca telefonda durur.

## Nasıl çalışır

- **Aralıklı tekrar (FSRS-5):** Her kart, hatırlama ihtimalin %90'a düşeceği gün geri gelir.
- **Kendini puanlama yok:** Cevabı uygulama kontrol eder, not doğru mu yanlış mı ve ne kadar sürdüğünden çıkar.
- **Basamaklar:** Yeni kelime önce gösterilir, 1 ve 10 dakika sonra şıklarla sorulur. Yerleşince şıklar önce aklından söyledikten sonra açılır. Bir gece geçince Türkçeden İngilizceye sorulur: önce şıkla, sonra yazarak. İki yön aynı gün gelmez.
- **Yük kontrolü:** Bekleyen tekrar günlük yeni kelimenin 15 katını geçince yeni kelimeler yarıya, 25 katını geçince sıfıra iner.
- **Gün sınırı:** Çalışma günü 04:00'te biter.

## Kelime verisi

`assets/deck.json`, `python -X utf8 tool/build_deck.py` ile üretilir. Girdiler `tool/data` altındadır:

| Dosya | İçerik | Kaynak ve lisans |
|---|---|---|
| `ngsl_stats.csv`, `ngsl_lemmas.csv` | Kelime sırası ve çekimleri | [NGSL 1.2](https://www.newgeneralservicelist.com), CC BY-SA 4.0 |
| `tr_1.txt`, `tr_2.txt` | Türkçe anlamlar | Bu proje için yazıldı |
| `own_sentences.txt` | Tatoeba'da uygun cümlesi olmayan kelimeler | Bu proje için yazıldı |
| `eng.bz2`, `tur.bz2`, `links.bz2` | Örnek cümleler (git'e girmez) | [Tatoeba](https://downloads.tatoeba.org/exports/per_language/), CC BY 2.0 FR |

Tatoeba dosyaları `eng/eng_sentences.tsv.bz2`, `tur/tur_sentences.tsv.bz2` ve `tur/tur-eng_links.tsv.bz2` adresindedir.

## Derleme

```
flutter test
flutter build apk --release
```

## İmzalama

Yayın anahtarı repoda durmaz: `C:\Users\Omega\.ezber-imza\`. Derleme `android/key.properties` dosyasını okur. Dosya yoksa release imzasız kalır. Anahtar kaybolursa hiçbir sürüm mevcut kurulumun üstüne kurulamaz. Her yayında `pubspec.yaml` içindeki `+` sonrasını artır.
