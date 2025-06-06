import React, { useState, useEffect } from 'react'
import consumer from '../channels/consumer'

const StockPrice = ({ symbol, marketPrice }) => {
  const [price, setPrice] = useState(marketPrice);
  
  useEffect(() => {
    const subscription = consumer.subscriptions.create(
      { channel: "PriceChannel", symbol: `A.${symbol}` },
	  
      { received(data) {
	      console.log(`Received data:`, data);
		  
		  
          setPrice(data);
		  
        }
      }
    );
    
    return () => {
      subscription.unsubscribe();
    };
  }, [symbol]);

  return <h2>${price}</h2>;
}

export default StockPrice;