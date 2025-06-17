import React, { useState, useEffect } from 'react';


const PortfolioValue = () => {
	
	const [value, setValue] = useState(null);
	
	useEffect(() => {
		async function getValue() {
			try {
				const response = await fetch('/aum')
				const data = await response.json()
				
				if (data === null) {
					setValue('N/A')
				} else {
				setValue(parseFloat(data).toFixed(2))
			}
			} catch (err) {
				console.log(err)
			}	
		}
		getValue();
		
		const interval = setInterval(getValue, 10000)
		
		return () => clearInterval(interval);
	
	}, []);
	
	return (
	
	<h2>{value}</h2>
	
	)

}

export default PortfolioValue