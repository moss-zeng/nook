# jcifs-ng 用了反射，保留其类
-keep class jcifs.** { *; }
-dontwarn jcifs.**

# slf4j 日志（jcifs 依赖），缺失的类忽略
-dontwarn org.slf4j.**
-keep class org.slf4j.** { *; }

# bouncycastle（jcifs 加密依赖，若有）
-dontwarn org.bouncycastle.**
-keep class org.bouncycastle.** { *; }