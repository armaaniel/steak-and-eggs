import React, { useState, useEffect } from 'react';
import consumer from '../channels/consumer'

const PositionsTable = ({ positions, id }) => {
 const [currentPositions, setCurrentPositions] = useState(positions);
 
 useEffect(() => {
   const subscription = consumer.subscriptions.create(
     { channel: "PortfolioChannel", id: `${id}` },
     { 
       received(data) {
         console.log(`Received data:`, data);
         
           setCurrentPositions(prevPositions => prevPositions.map(position => ({...position, price: data.stock_prices[position.symbol] || position.price
             }))
           );
         }
	 }
   );
 
   return () => {
     subscription.unsubscribe();
   };
 }, [id]);

 return (
   <>
     <table className="portfolio">
       <thead>
         <tr className="heading-row">
           <th className="positions-header">Positions</th>
           <th className="quantity-header">Total Value</th>
           <th className="quantity-header">Today's Price</th>
         </tr>
       </thead>
       
       <tbody>
         {currentPositions.map((position) => (
           <tr key={position.symbol} className="portfolio-row">
             
             <td className="symbol-cell">
               <a href={`/stocks/${position.symbol}`} className="symbol-name">
                 <img src={`https://img.logo.dev/ticker/${position.symbol}?token=pk_ZBCJebqoQXKBWVLhwcIBfg&retina=true`} height="32" width="32"/>
                 
                 <div className="stock-text">
                   <p className="stock-symbol">{position.symbol}</p>
                   <p className="stock-name">{position.name}</p>
                 </div>
               </a>
             </td>
             
             <td className="shares-cell">
               <a href={`/stocks/${position.symbol}`} className="symbol-name">
                 <div className='stock-text'>
                   <p className='stock-symbol'>${(position.price * position.shares).toFixed(2)} </p>
                   <p className='stock-name'>{position.shares} shares</p>
				   
                 </div>
               </a>
             </td>
             
             <td className="shares-cell">
               <a href={`/stocks/${position.symbol}`} className="symbol-name">
                 <div className='stock-text'>
                   <p className='stock-name'>${position.price.toFixed(2)}</p>
                 </div>
               </a>
             </td>
             
           </tr>
         ))}
       </tbody>
     </table>
   </>
 );
};

export default PositionsTable;