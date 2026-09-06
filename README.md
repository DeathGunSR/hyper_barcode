# Barcode Scanner Flutter App

یک اپلیکیشن اندروید برای اسکن بارکد محصولات به صورت پشت سر هم و ذخیره در فایل اکسل.

## ویژگی‌ها
- اسکن بارکد با دوربین گوشی به صورت مداوم
- دکمه شاتر برای اسکن تک‌تک بارکدها
- ثبت دستی بارکد
- نمایش لیست بارکدهای اسکن شده
- خروجی اکسل با بارکدها در ستون جداگانه
- اشتراک‌گذاری فایل اکسل با سایر برنامه‌ها
- پشتیبانی از زبان انگلیسی برای بارکدها و متون

## پیش‌نیازها
- نصب Flutter SDK (نسخه 3.0 یا بالاتر)
- نصب Android Studio یا VS Code با افزونه Flutter
- نصب Git
- دسترسی به اینترنت برای دانلود وابستگی‌ها

## راه‌اندازی پروژه

### 1. کلون کردن پروژه
```bash
git clone <repository-url>
cd barcode_scanner_app
```

### 2. نصب وابستگی‌ها
```bash
flutter pub get
```

### 3. تنظیمات Android
فایل `android/app/build.gradle` را بررسی کنید و مطمئن شوید که `minSdkVersion` حداقل 21 باشد.

همچنین مجوزهای لازم را در فایل `android/app/src/main/AndroidManifest.xml` اضافه کنید:
```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
```

### 4. اجرای اپلیکیشن
```bash
flutter run
```

## ساخت فایل APK

### ساخت APK برای تست (Debug)
```bash
flutter build apk --debug
```

### ساخت APK نهایی (Release)
```bash
flutter build apk --release
```

خروجی در مسیر `build/app/outputs/flutter-apk/app-release.apk` قرار می‌گیرد.

## ساخت با GitHub Actions

برای ساخت خودکار APK با GitHub:

1. پوشه `.github/workflows` را ایجاد کنید
2. فایل `flutter.yml` را با محتوای زیر ایجاد کنید:

```yaml
name: Build Flutter APK

on:
  push:
    branches: [ main, master ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup Java
        uses: actions/setup-java@v3
        with:
          java-version: "17"
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: "3.19.0"
      - run: flutter pub get
      - run: flutter build apk --release
      - uses: actions/upload-artifact@v3
        with:
          name: release-apk
          path: build/app/outputs/flutter-apk/app-release.apk
```

## نحوه استفاده

1. **اسکن بارکد**: دوربین به صورت خودکار بارکدها را اسکن می‌کند
2. **دکمه Shutter**: برای اسکن دستی هر بارکد
3. **Add Barcode**: ثبت دستی بارکد
4. **Show List**: نمایش لیست بارکدها
5. **Export Excel**: ذخیره فایل اکسل (انتخاب مسیر)
6. **Share Excel**: اشتراک‌گذاری فایل اکسل

## عیب‌یابی

- دستور `flutter doctor` را برای بررسی مشکلات اجرا کنید
- مطمئن شوید مجوز دوربین داده شده است
