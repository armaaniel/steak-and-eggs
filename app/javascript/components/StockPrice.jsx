import React, { useState, useEffect } from 'react'
import consumer from '../channels/consumer'

const StockPrice = ({ symbol, marketPrice, currency }) => {
  const [price, setPrice] = useState(parseFloat(marketPrice).toFixed(2));
  
  useEffect(() => {
    const subscription = consumer.subscriptions.create(
      { channel: "PriceChannel", symbol: `${symbol}` },
	  
      { received(data) {
	      console.log(`Received data:`, data);
		  
		  
          setPrice(parseFloat(data).toFixed(2));
		  
        }
      }
    );
    
    return () => {
      subscription.unsubscribe();
    };
  }, [symbol]);

  return (
  <>
  <h3 className='stock-price-header'>${price}</h3>
  <span className='stock-price-currency'>{currency}</span>
  </>
  
  )
}

export default StockPrice;