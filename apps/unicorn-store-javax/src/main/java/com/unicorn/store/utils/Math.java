package com.unicorn.store.utils;
import java.math.BigDecimal;

public class Math {
    Boolean bool = new Boolean(true);
    Byte b = new Byte("1");
    Character c = new Character('c');
    Double d = new Double(1.0);
    Float f = new Float(1.1f);
    Long l = new Long(1L);
    Short sh = new Short("12");
    Short s3 = 3;
    Integer i = new Integer(1);

    void divide(){
        BigDecimal bd = BigDecimal.valueOf(10);
        BigDecimal bd2 = BigDecimal.valueOf(3);
        bd.divide(bd2, BigDecimal.ROUND_DOWN);
        bd.divide(bd2, 1);
        bd.divide(bd2, 1, BigDecimal.ROUND_DOWN);
        bd.divide(bd2, 1,1);
        bd.setScale(2,1);
    }
}