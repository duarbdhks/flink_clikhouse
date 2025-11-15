package com.flink.common.config;

import java.io.IOException;
import java.io.InputStream;
import java.util.Properties;

/**
 * Properties 파일을 읽어서 설정 값을 제공하는 공통 유틸리티 클래스
 * 모든 Flink Job에서 공통으로 사용할 수 있습니다.
 */
public class ConfigLoader {

    private static final String CONFIG_FILE = "application.properties";
    private static final Properties properties = new Properties();

    static {
        loadProperties();
    }

    /**
     * application.properties 파일을 로드합니다.
     */
    private static void loadProperties() {
        try (InputStream input = ConfigLoader.class.getClassLoader().getResourceAsStream(CONFIG_FILE)) {
            if (input == null) {
                throw new RuntimeException("Unable to find " + CONFIG_FILE);
            }
            properties.load(input);
        } catch (IOException e) {
            throw new RuntimeException("Failed to load configuration from " + CONFIG_FILE, e);
        }
    }

    /**
     * 설정 값을 가져옵니다.
     *
     * @param key 설정 키
     * @return 설정 값
     */
    public static String get(String key) {
        return properties.getProperty(key);
    }

    /**
     * 설정 값을 가져오며, 값이 없으면 기본값을 반환합니다.
     *
     * @param key          설정 키
     * @param defaultValue 기본값
     * @return 설정 값 또는 기본값
     */
    public static String get(String key, String defaultValue) {
        return properties.getProperty(key, defaultValue);
    }

    /**
     * 정수형 설정 값을 가져옵니다.
     *
     * @param key 설정 키
     * @return 정수형 설정 값
     */
    public static int getInt(String key) {
        return Integer.parseInt(get(key));
    }

    /**
     * 정수형 설정 값을 가져오며, 값이 없으면 기본값을 반환합니다.
     *
     * @param key          설정 키
     * @param defaultValue 기본값
     * @return 정수형 설정 값 또는 기본값
     */
    public static int getInt(String key, int defaultValue) {
        String value = get(key);
        return value != null ? Integer.parseInt(value) : defaultValue;
    }

    /**
     * Long형 설정 값을 가져옵니다.
     *
     * @param key 설정 키
     * @return Long형 설정 값
     */
    public static long getLong(String key) {
        return Long.parseLong(get(key));
    }

    /**
     * Long형 설정 값을 가져오며, 값이 없으면 기본값을 반환합니다.
     *
     * @param key          설정 키
     * @param defaultValue 기본값
     * @return Long형 설정 값 또는 기본값
     */
    public static long getLong(String key, long defaultValue) {
        String value = get(key);
        return value != null ? Long.parseLong(value) : defaultValue;
    }

    /**
     * Boolean형 설정 값을 가져옵니다.
     *
     * @param key 설정 키
     * @return Boolean형 설정 값
     */
    public static boolean getBoolean(String key) {
        return Boolean.parseBoolean(get(key));
    }

    /**
     * Boolean형 설정 값을 가져오며, 값이 없으면 기본값을 반환합니다.
     *
     * @param key          설정 키
     * @param defaultValue 기본값
     * @return Boolean형 설정 값 또는 기본값
     */
    public static boolean getBoolean(String key, boolean defaultValue) {
        String value = get(key);
        return value != null ? Boolean.parseBoolean(value) : defaultValue;
    }
}
