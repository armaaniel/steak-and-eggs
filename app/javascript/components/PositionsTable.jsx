import React, { useState, useEffect } from 'react';

const PositionsTable = ({ id }) => {
 const [positions, setPositions] = useState([]);

 useEffect(() => {
   const getPositions = async () => {
     try {
       const response = await fetch('/positions');
       const data = await response.json();
       setPositions(data);
     } catch (err) {
       console.log(err);
     }
   };

   getPositions();
   const interval = setInterval(getPositions, 5000);
   
   return () => clearInterval(interval);
 }, []);

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
		 
           {positions.map((position) => (
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
                   <p className='stock-symbol'>${position.shares * position.price} USD</p>
				   <p className='stock-name'>{position.shares} shares</p>
				 </div>
                 </a>
				 
               </td>
			   
               <td className="shares-cell">
			   
                 <a href={`/stocks/${position.symbol}`} className="symbol-name">
				 <div className='stock-text'>
                   <p className='stock-name'>${position.price} USD</p>
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