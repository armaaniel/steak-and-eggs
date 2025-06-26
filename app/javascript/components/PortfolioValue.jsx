import React, { useState, useEffect } from 'react'
import consumer from '../channels/consumer'

const PortfolioValue = ({ id, aum }) => {
  const [value, setValue] = useState(parseFloat(aum).toFixed(2))
  
  useEffect(() => {
    const subscription = consumer.subscriptions.create(
      { channel: "PortfolioChannel", id: `${id}` },
	  
      { received(data) {
	      console.log(`Received data:`, data);
		  
		  
          setValue(parseFloat(data.portfolio_value).toFixed(2));
		  
        }
      }
    );
    
    return () => {
      subscription.unsubscribe();
    };
  }, [id]);

  return (
  <>
  <h2 className='port-value'>${value}</h2>
  </>
  
  )
}

export default PortfolioValue;