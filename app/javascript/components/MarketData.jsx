import React, {useState, useEffect} from 'react'

const MarketData = ({symbol}) => {
	
	const [marketData, setMarketData] = useState(null)
	const [companyData, setCompanyData] = useState(null)
	
	useEffect(() => {
		async function getData() {
			try {
				const [response1, response2] = await Promise.all([
				fetch (`/stocks/${symbol}/marketdata`),
				fetch (`/stocks/${symbol}/companydata`)
				])
				
				const data1 = await response1.json()
				const data2 = await response2.json()
				
				setMarketData(data1)
				setCompanyData(data2)
				
				console.log(data1)
				console.log(data2)
				
			} catch (error) {
				console.error(error)
			}
		} getData()
	}, [symbol])
	
	return (
	
	<>
	
    <div className="market-data">
	
	<div>
		<p class='data-name'>Open</p>
		<p class='data-value'>{marketData ? marketData.open : <span className='skeleton-data-value'></span>}</p>
	</div>
		
	<div>
		<p class='data-name'>52 week high</p>
		<p class='data-value'>{companyData ? companyData['52_week_high'] : <span className="skeleton-data-value"></span>}</p>
	</div>
	
	<div>
		<p class='data-name'>Exchange</p>
		<p class='data-value'>{companyData ? companyData.exchange : <span className="skeleton-data-value"></span>}</p>
	</div>
	
	<div>
		<p class='data-name'>High</p>
		<p class='data-value'>{marketData ? marketData.high : <span className="skeleton-data-value"></span>}</p>
	</div>
	
	<div class>
		<p class='data-name'>52 week low</p>
		<p class='data-value'>{companyData ? companyData['52_week_low'] : <span className="skeleton-data-value"></span>}</p>
	</div>
	
	<div>
		<p class='data-name'>Market cap</p>
		<p class='data-value'>$	{companyData ? companyData.market_capitalization : <span className="skeleton-data-value"></span>}</p>
	</div>
		
	
	<div>
		<p class='data-name'>Low</p>
		<p class='data-value'>{marketData ? marketData.low : <span className="skeleton-data-value"></span>}</p>
	</div>
	
	
	<div>
		<p class='data-name'>Volume</p>
		<p class='data-value'>{marketData ? marketData.volume : <span className="skeleton-data-value"></span>}</p>
	</div>
	
	
	<div>
		<p class='data-name'>Currency</p>
		<p class='data-value'>{companyData ? companyData.currency : <span className="skeleton-data-value"></span>}</p>
	</div>
	
	</div>
	
	<div class='stock-description'>
		<h2 class='header-data-name'>Description</h2>
		<p class='data-value'>{companyData ? companyData.description : <span className="skeleton-description"></span>}</p>
	</div>
	
	</>
	
	)
	
	
}

export default MarketData